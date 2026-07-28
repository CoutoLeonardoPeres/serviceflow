-- =============================================================================
-- Migration: 0051_appointment_events
-- Descricao: Rastreabilidade da agenda (agendado / cancelado / reagendado) e
--            liberacao do agendamento de ordem de servico — F5-P1 (ADR-027)
-- Depende de: 0001_foundation, 0004_scheduling, 0005_work_orders
-- Rollback: supabase/rollbacks/0051_appointment_events_rollback.sql
--
-- ORIGEM: a agenda passou a operar por fila — chamados e OS aguardando
-- agendamento aparecem para todos os profissionais da categoria, sao
-- arrastados para um horario e, ao cancelar, voltam para a fila de todos.
-- Esse vai-e-volta precisa de historico proprio: quem agendou, quem cancelou,
-- por que, e qual era o horario antes. `audit_logs` guarda a acao, mas em
-- formato generico demais para virar indicador de produtividade e custo.
--
-- DOIS DEFEITOS PRE-EXISTENTES CORRIGIDOS AQUI:
--   1. `appointments.reference_id` tinha FK rigida para `service_requests`,
--      mesmo quando `kind = 'work_order'`. Como a FK nunca poderia ser
--      satisfeita por uma OS, agendar OS era impossivel. A checagem vira
--      responsabilidade do trigger de meta, que ja valida tenant por tipo.
--   2. `schedule_appointment` rejeitava `p_kind <> 'visit'` com "ainda nao
--      suportado no MVP". A UI ja oferecia "Agendar OS" ha varias entregas,
--      entao a chamada falhava no banco.
--
-- MODELO: `appointment_events` e append-only (sem UPDATE/DELETE) e alimentada
-- por trigger em `appointments`, nao pela aplicacao — assim qualquer caminho
-- que mexa na agenda fica registrado, inclusive RPC e correcao manual.
-- =============================================================================

-- ── 1. reference_id: FK rigida vira validacao por tipo no trigger ───────────
--
-- EFEITO COLATERAL NO POSTGREST: o embed `service_requests(title)` dentro de
-- um select em `appointments` era resolvido por esta FK. Sem ela, o
-- relacionamento some do schema cache e a consulta passa a responder
-- PGRST200 ("could not find a relationship"). O app deixou de usar o embed e
-- resolve o titulo em consulta separada, por tipo — ver
-- `AppointmentRepository._attachReferenceTitles`. Um embed aqui nunca foi
-- correto de qualquer forma: para `kind = 'work_order'` o titulo vem de
-- `work_orders`, nao de `service_requests`.

ALTER TABLE appointments
  DROP CONSTRAINT IF EXISTS appointments_reference_id_fkey;

CREATE OR REPLACE FUNCTION _sf_set_appointment_meta()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    IF NEW.tenant_id IS NULL THEN
      RAISE EXCEPTION 'tenant_id e obrigatorio em seed/operacao administrativa.';
    END IF;
  ELSE
    NEW.tenant_id := current_tenant_id();
  END IF;

  SELECT tenant_id INTO v_tenant_id FROM customers WHERE id = NEW.customer_id;
  IF v_tenant_id IS NULL OR v_tenant_id <> NEW.tenant_id THEN
    RAISE EXCEPTION 'Cliente inexistente ou fora do tenant autorizado.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF NEW.address_id IS NOT NULL THEN
    SELECT tenant_id INTO v_tenant_id FROM customer_addresses WHERE id = NEW.address_id;
    IF v_tenant_id IS NULL OR v_tenant_id <> NEW.tenant_id THEN
      RAISE EXCEPTION 'Endereco fora do tenant autorizado.'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  IF NEW.kind = 'visit' THEN
    SELECT tenant_id INTO v_tenant_id FROM service_requests WHERE id = NEW.reference_id;
    IF v_tenant_id IS NULL OR v_tenant_id <> NEW.tenant_id THEN
      RAISE EXCEPTION 'Chamado fora do tenant autorizado.'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  ELSIF NEW.kind = 'work_order' THEN
    SELECT tenant_id INTO v_tenant_id FROM work_orders WHERE id = NEW.reference_id;
    IF v_tenant_id IS NULL OR v_tenant_id <> NEW.tenant_id THEN
      RAISE EXCEPTION 'Ordem de servico fora do tenant autorizado.'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.created_by := auth.uid();
    NEW.updated_by := auth.uid();
  ELSE
    NEW.tenant_id := OLD.tenant_id;
    NEW.updated_by := auth.uid();
  END IF;

  RETURN NEW;
END;
$$;

-- ── 2. Historico da agenda ──────────────────────────────────────────────────

CREATE TABLE appointment_events (
  id                 uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id          uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  appointment_id     uuid        NOT NULL REFERENCES appointments(id) ON DELETE CASCADE,
  event_type         text        NOT NULL CHECK (event_type IN (
                                   'scheduled','rescheduled','cancelled',
                                   'status_changed'
                                 )),
  kind               text        NOT NULL CHECK (kind IN ('visit','work_order')),
  reference_id       uuid        NOT NULL,
  customer_id        uuid        NOT NULL REFERENCES customers(id),
  technician_user_id uuid        REFERENCES profiles(id),
  previous_status    text,
  new_status         text,
  previous_start     timestamptz,
  new_start          timestamptz,
  reason             text        CHECK (reason IS NULL OR char_length(reason) <= 500),
  created_at         timestamptz NOT NULL DEFAULT now(),
  created_by         uuid        REFERENCES auth.users(id)
);

-- Ordenacao estavel por agendamento: created_at empata em operacoes na mesma
-- transacao, entao o id entra como desempate (mesma licao da 0050).
CREATE INDEX idx_appointment_events_appointment
  ON appointment_events (appointment_id, created_at DESC, id DESC);
CREATE INDEX idx_appointment_events_tenant_created
  ON appointment_events (tenant_id, created_at DESC);
CREATE INDEX idx_appointment_events_reference
  ON appointment_events (tenant_id, kind, reference_id, created_at DESC);
-- Recorte direto das perguntas de BI: quanto cada tecnico cancelou no periodo.
CREATE INDEX idx_appointment_events_technician
  ON appointment_events (tenant_id, technician_user_id, event_type, created_at DESC);

-- ── 3. Trigger que alimenta o historico ─────────────────────────────────────
-- Roda AFTER, porque precisa do id do appointment no INSERT e do tecnico ja
-- atribuido. No INSERT o assignment ainda nao existe (schedule_appointment
-- insere o appointment antes do assignment), entao o tecnico fica nulo no
-- evento 'scheduled' e e preenchido pelo proprio schedule_appointment.

CREATE OR REPLACE FUNCTION _sf_log_appointment_event()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_event_type text;
  v_technician uuid;
BEGIN
  IF TG_OP = 'INSERT' THEN
    v_event_type := 'scheduled';
  ELSIF NEW.status = 'cancelled' AND OLD.status <> 'cancelled' THEN
    v_event_type := 'cancelled';
  ELSIF NEW.scheduled_start <> OLD.scheduled_start
     OR NEW.scheduled_end <> OLD.scheduled_end THEN
    v_event_type := 'rescheduled';
  ELSIF NEW.status <> OLD.status THEN
    v_event_type := 'status_changed';
  ELSE
    RETURN NEW;
  END IF;

  SELECT aa.technician_user_id INTO v_technician
  FROM appointment_assignments aa
  WHERE aa.appointment_id = NEW.id
    AND aa.revoked_at IS NULL
  ORDER BY aa.assigned_at
  LIMIT 1;

  INSERT INTO appointment_events (
    tenant_id, appointment_id, event_type, kind, reference_id, customer_id,
    technician_user_id, previous_status, new_status,
    previous_start, new_start, created_by
  ) VALUES (
    NEW.tenant_id, NEW.id, v_event_type, NEW.kind, NEW.reference_id,
    NEW.customer_id, v_technician,
    CASE WHEN TG_OP = 'UPDATE' THEN OLD.status END,
    NEW.status,
    CASE WHEN TG_OP = 'UPDATE' THEN OLD.scheduled_start END,
    NEW.scheduled_start,
    auth.uid()
  );

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_appointments_events
  AFTER INSERT OR UPDATE ON appointments
  FOR EACH ROW EXECUTE FUNCTION _sf_log_appointment_event();

-- ── 4. schedule_appointment: liberar OS ─────────────────────────────────────

CREATE OR REPLACE FUNCTION schedule_appointment(
  p_kind text,
  p_reference_id uuid,
  p_customer_id uuid,
  p_address_id uuid,
  p_scheduled_start timestamptz,
  p_scheduled_end timestamptz,
  p_technician_user_id uuid,
  p_notes text DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_appointment_id uuid;
  v_is_technician boolean;
  v_reference_tenant uuid;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'Nenhuma membership ativa encontrada.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF NOT has_permission('appointments.write') THEN
    RAISE EXCEPTION 'Permissao insuficiente para agendar.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_kind NOT IN ('visit','work_order') THEN
    RAISE EXCEPTION 'Tipo de agendamento invalido: %', p_kind
      USING ERRCODE = 'check_violation';
  END IF;

  IF p_scheduled_end <= p_scheduled_start THEN
    RAISE EXCEPTION 'Periodo de agendamento invalido.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF p_kind = 'visit' THEN
    SELECT tenant_id INTO v_reference_tenant
    FROM service_requests WHERE id = p_reference_id;
  ELSE
    SELECT tenant_id INTO v_reference_tenant
    FROM work_orders WHERE id = p_reference_id;
  END IF;

  IF v_reference_tenant IS NULL OR v_reference_tenant <> v_tenant_id THEN
    RAISE EXCEPTION 'Chamado ou ordem de servico fora do tenant autorizado.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM tenant_memberships tm
    JOIN roles r ON r.id = tm.role_id
    WHERE tm.tenant_id = v_tenant_id
      AND tm.user_id = p_technician_user_id
      AND tm.status = 'active'
      AND r.key = 'technician'
  ) INTO v_is_technician;

  IF NOT v_is_technician THEN
    RAISE EXCEPTION 'Usuario selecionado nao e tecnico ativo do tenant.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_tenant_id::text || ':' || p_technician_user_id::text));

  IF EXISTS (
    SELECT 1
    FROM appointment_assignments aa
    JOIN appointments a ON a.id = aa.appointment_id
    WHERE aa.tenant_id = v_tenant_id
      AND aa.technician_user_id = p_technician_user_id
      AND aa.revoked_at IS NULL
      AND a.status NOT IN ('cancelled','no_show')
      AND tstzrange(a.scheduled_start, a.scheduled_end, '[)') &&
          tstzrange(p_scheduled_start, p_scheduled_end, '[)')
  ) THEN
    RAISE EXCEPTION 'Este tecnico ja possui atendimento neste periodo.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- O item so pode estar na fila de um profissional por vez: se ja existe
  -- agendamento ativo para esta referencia, o arrasto de outro operador nao
  -- pode criar um segundo. O advisory lock acima e por tecnico, entao esta
  -- checagem precisa do seu proprio lock, por referencia.
  PERFORM pg_advisory_xact_lock(hashtext(v_tenant_id::text || ':' || p_kind || ':' || p_reference_id::text));

  IF EXISTS (
    SELECT 1 FROM appointments
    WHERE tenant_id = v_tenant_id
      AND kind = p_kind
      AND reference_id = p_reference_id
      AND status <> 'cancelled'
  ) THEN
    RAISE EXCEPTION 'Este item ja esta agendado para outro profissional.'
      USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO appointments (
    tenant_id, kind, reference_id, customer_id, address_id,
    scheduled_start, scheduled_end, status, notes
  ) VALUES (
    v_tenant_id, p_kind, p_reference_id, p_customer_id, p_address_id,
    p_scheduled_start, p_scheduled_end, 'scheduled', p_notes
  )
  RETURNING id INTO v_appointment_id;

  INSERT INTO appointment_assignments (
    appointment_id, technician_user_id
  ) VALUES (
    v_appointment_id, p_technician_user_id
  );

  IF p_kind = 'visit' THEN
    INSERT INTO technical_visits (
      request_id, appointment_id, technician_id
    ) VALUES (
      p_reference_id, v_appointment_id, p_technician_user_id
    );
  END IF;

  -- O evento 'scheduled' nasce do trigger antes do assignment existir, entao
  -- o tecnico e preenchido aqui.
  UPDATE appointment_events
  SET technician_user_id = p_technician_user_id
  WHERE appointment_id = v_appointment_id
    AND event_type = 'scheduled'
    AND technician_user_id IS NULL;

  PERFORM log_audit(
    v_tenant_id,
    'appointment.scheduled',
    'appointments',
    v_appointment_id::text,
    NULL,
    jsonb_build_object(
      'kind', p_kind,
      'reference_id', p_reference_id,
      'technician_user_id', p_technician_user_id,
      'scheduled_start', p_scheduled_start,
      'scheduled_end', p_scheduled_end
    )
  );

  RETURN v_appointment_id;
END;
$$;

-- ── 5. Cancelamento: devolve o item para a fila da categoria ────────────────
-- O tecnico de campo tambem cancela, entao a permissao aceita quem tem
-- appointments.write OU e o tecnico atribuido ao proprio atendimento.

CREATE OR REPLACE FUNCTION cancel_appointment(
  p_appointment_id uuid,
  p_reason text DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_appointment appointments%ROWTYPE;
  v_is_assigned boolean;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'Nenhuma membership ativa encontrada.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_appointment
  FROM appointments
  WHERE id = p_appointment_id AND tenant_id = v_tenant_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Agendamento nao encontrado.'
      USING ERRCODE = 'no_data_found';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM appointment_assignments
    WHERE appointment_id = p_appointment_id
      AND technician_user_id = auth.uid()
      AND revoked_at IS NULL
  ) INTO v_is_assigned;

  IF NOT has_permission('appointments.write') AND NOT v_is_assigned THEN
    RAISE EXCEPTION 'Permissao insuficiente para cancelar este atendimento.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_appointment.status = 'cancelled' THEN
    RETURN p_appointment_id;
  END IF;

  IF v_appointment.status = 'done' THEN
    RAISE EXCEPTION 'Atendimento ja realizado nao pode ser cancelado.'
      USING ERRCODE = 'check_violation';
  END IF;

  UPDATE appointments
  SET status = 'cancelled'
  WHERE id = p_appointment_id;

  -- Libera o tecnico da janela: sem isso o horario continuaria bloqueado
  -- pela checagem de sobreposicao do schedule_appointment.
  UPDATE appointment_assignments
  SET revoked_at = now()
  WHERE appointment_id = p_appointment_id
    AND revoked_at IS NULL;

  UPDATE appointment_events
  SET reason = p_reason
  WHERE appointment_id = p_appointment_id
    AND event_type = 'cancelled'
    AND reason IS NULL;

  PERFORM log_audit(
    v_tenant_id,
    'appointment.cancelled',
    'appointments',
    p_appointment_id::text,
    jsonb_build_object('status', v_appointment.status),
    jsonb_build_object('status', 'cancelled', 'reason', p_reason)
  );

  RETURN p_appointment_id;
END;
$$;

-- ── 6. RLS ──────────────────────────────────────────────────────────────────
-- Append-only: sem policy de UPDATE nem DELETE para `authenticated`. As
-- funcoes acima ajustam linhas via SECURITY DEFINER, que ignora RLS.

ALTER TABLE appointment_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "appointment_events_select" ON appointment_events
  FOR SELECT TO authenticated
  USING (tenant_id = current_tenant_id() AND has_permission('appointments.read'));

GRANT EXECUTE ON FUNCTION cancel_appointment(uuid, text) TO authenticated;

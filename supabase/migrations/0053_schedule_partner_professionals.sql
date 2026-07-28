-- =============================================================================
-- Migration: 0053_schedule_partner_professionals
-- Descricao: Agendar profissional sem usuario do sistema — F5-P4 (ADR-028)
-- Depende de: 0004_scheduling, 0018_service_professionals, 0052_appointment_multi_technician
-- Rollback: supabase/rollbacks/0053_schedule_partner_professionals_rollback.sql
--
-- ORIGEM: `service_professionals` nasceu (0018) com `linked_user_id` opcional
-- e o comentario da coluna dizia o resto: "quando preenchido, o profissional
-- pode receber agenda". Ou seja, parceiro externo sem login do sistema nunca
-- foi agendavel — mas a tela de profissionais permite cadastra-lo, e a
-- expectativa de quem cadastra e justamente poder agenda-lo. Na pratica o
-- arrasto na agenda respondia "Fulano nao tem usuario vinculado — agende pelo
-- formulario", e o formulario dizia a mesma coisa: nao havia caminho nenhum.
--
-- DECISAO: `appointment_assignments` passa a apontar para o profissional
-- (`professional_id`), com `technician_user_id` opcional e preenchido apenas
-- quando existe usuario vinculado. Quem tem login continua ganhando o vinculo
-- com `profiles` (e portanto acesso ao proprio atendimento no app de campo);
-- quem nao tem entra na agenda do mesmo jeito, so nao enxerga o app.
--
-- ponytail: nao cria usuario "fantasma" em `profiles` para o parceiro. Seria
-- mais barato no curto prazo (nada muda no resto do sistema), mas polui a
-- tabela de identidade com linhas que nunca autenticam e faz RLS por
-- `auth.uid()` mentir. Agenda e identidade sao coisas diferentes.
-- =============================================================================

-- ── 1. appointment_assignments aceita profissional sem usuario ──────────────

ALTER TABLE appointment_assignments
  ADD COLUMN IF NOT EXISTS professional_id uuid REFERENCES service_professionals(id);

ALTER TABLE appointment_assignments
  ALTER COLUMN technician_user_id DROP NOT NULL;

-- Backfill: liga os assignments existentes ao profissional correspondente.
UPDATE appointment_assignments aa
SET professional_id = sp.id
FROM service_professionals sp
WHERE aa.professional_id IS NULL
  AND sp.tenant_id = aa.tenant_id
  AND sp.linked_user_id = aa.technician_user_id;

ALTER TABLE appointment_assignments
  DROP CONSTRAINT IF EXISTS chk_appointment_assignment_target;

ALTER TABLE appointment_assignments
  ADD CONSTRAINT chk_appointment_assignment_target
  CHECK (technician_user_id IS NOT NULL OR professional_id IS NOT NULL);

-- A unica antiga era (appointment_id, technician_user_id); com NULL permitido
-- ela deixa de impedir duplicata de parceiro. A chave passa a ser o
-- profissional, que existe nos dois casos.
CREATE UNIQUE INDEX IF NOT EXISTS uq_appointment_active_professional
  ON appointment_assignments (appointment_id, professional_id)
  WHERE professional_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_appointment_assignments_professional
  ON appointment_assignments (tenant_id, professional_id)
  WHERE revoked_at IS NULL;

-- O trigger de meta resolvia o tenant pelo appointment; segue valendo.

-- ── 2. Helper de resolucao e conflito ───────────────────────────────────────

CREATE OR REPLACE FUNCTION _sf_professional_busy(
  p_tenant_id uuid,
  p_professional_id uuid,
  p_start timestamptz,
  p_end timestamptz,
  p_ignore_appointment uuid DEFAULT NULL
) RETURNS boolean LANGUAGE sql STABLE
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM appointment_assignments aa
    JOIN appointments a ON a.id = aa.appointment_id
    WHERE aa.tenant_id = p_tenant_id
      AND aa.professional_id = p_professional_id
      AND aa.revoked_at IS NULL
      AND (p_ignore_appointment IS NULL OR a.id <> p_ignore_appointment)
      AND a.status NOT IN ('cancelled','no_show')
      AND tstzrange(a.scheduled_start, a.scheduled_end, '[)') &&
          tstzrange(p_start, p_end, '[)')
  );
$$;

-- ── 3. schedule_appointment por profissional ────────────────────────────────
-- `p_technician_user_id` continua na assinatura por compatibilidade, mas agora
-- e opcional: o que manda e `p_professional_id`.

CREATE OR REPLACE FUNCTION schedule_appointment(
  p_kind text,
  p_reference_id uuid,
  p_customer_id uuid,
  p_address_id uuid,
  p_scheduled_start timestamptz,
  p_scheduled_end timestamptz,
  p_technician_user_id uuid DEFAULT NULL,
  p_notes text DEFAULT NULL,
  p_professional_id uuid DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_appointment_id uuid;
  v_reference_tenant uuid;
  v_professional service_professionals%ROWTYPE;
  v_user_id uuid;
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

  -- Resolve o profissional: por id direto, ou pelo usuario vinculado quando a
  -- chamada veio no formato antigo.
  IF p_professional_id IS NOT NULL THEN
    SELECT * INTO v_professional
    FROM service_professionals
    WHERE id = p_professional_id AND tenant_id = v_tenant_id AND is_active;
  ELSIF p_technician_user_id IS NOT NULL THEN
    SELECT * INTO v_professional
    FROM service_professionals
    WHERE linked_user_id = p_technician_user_id
      AND tenant_id = v_tenant_id AND is_active;
  END IF;

  IF v_professional.id IS NULL THEN
    RAISE EXCEPTION 'Profissional nao encontrado ou inativo.'
      USING ERRCODE = 'no_data_found';
  END IF;

  v_user_id := v_professional.linked_user_id;

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

  PERFORM pg_advisory_xact_lock(hashtext(v_tenant_id::text || ':' || v_professional.id::text));

  IF _sf_professional_busy(
       v_tenant_id, v_professional.id, p_scheduled_start, p_scheduled_end
     ) THEN
    RAISE EXCEPTION 'Este profissional ja possui atendimento neste periodo.'
      USING ERRCODE = 'check_violation';
  END IF;

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
    appointment_id, technician_user_id, professional_id
  ) VALUES (
    v_appointment_id, v_user_id, v_professional.id
  );

  -- technical_visits.technician_id referencia profiles: fica nulo para
  -- parceiro sem login, que e exatamente o que a coluna nullable permite.
  IF p_kind = 'visit' THEN
    INSERT INTO technical_visits (
      request_id, appointment_id, technician_id
    ) VALUES (
      p_reference_id, v_appointment_id, v_user_id
    );
  END IF;

  UPDATE appointment_events
  SET technician_user_id = v_user_id
  WHERE appointment_id = v_appointment_id
    AND event_type = 'scheduled'
    AND technician_user_id IS NULL
    AND v_user_id IS NOT NULL;

  PERFORM log_audit(
    v_tenant_id,
    'appointment.scheduled',
    'appointments',
    v_appointment_id::text,
    NULL,
    jsonb_build_object(
      'kind', p_kind,
      'reference_id', p_reference_id,
      'professional_id', v_professional.id,
      'technician_user_id', v_user_id,
      'scheduled_start', p_scheduled_start,
      'scheduled_end', p_scheduled_end
    )
  );

  RETURN v_appointment_id;
END;
$$;

-- ── 4. assign/unassign por profissional ─────────────────────────────────────

CREATE OR REPLACE FUNCTION assign_technician(
  p_appointment_id uuid,
  p_technician_user_id uuid DEFAULT NULL,
  p_professional_id uuid DEFAULT NULL
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_appointment appointments%ROWTYPE;
  v_professional service_professionals%ROWTYPE;
  v_assignment_id uuid;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'Nenhuma membership ativa encontrada.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF NOT has_permission('appointments.write') THEN
    RAISE EXCEPTION 'Permissao insuficiente para atribuir profissional.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_appointment
  FROM appointments
  WHERE id = p_appointment_id AND tenant_id = v_tenant_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Agendamento nao encontrado.'
      USING ERRCODE = 'no_data_found';
  END IF;

  IF v_appointment.status IN ('cancelled','done') THEN
    RAISE EXCEPTION 'Atendimento encerrado nao aceita novo profissional.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF p_professional_id IS NOT NULL THEN
    SELECT * INTO v_professional
    FROM service_professionals
    WHERE id = p_professional_id AND tenant_id = v_tenant_id AND is_active;
  ELSIF p_technician_user_id IS NOT NULL THEN
    SELECT * INTO v_professional
    FROM service_professionals
    WHERE linked_user_id = p_technician_user_id
      AND tenant_id = v_tenant_id AND is_active;
  END IF;

  IF v_professional.id IS NULL THEN
    RAISE EXCEPTION 'Profissional nao encontrado ou inativo.'
      USING ERRCODE = 'no_data_found';
  END IF;

  PERFORM pg_advisory_xact_lock(hashtext(v_tenant_id::text || ':' || v_professional.id::text));

  SELECT id INTO v_assignment_id
  FROM appointment_assignments
  WHERE appointment_id = p_appointment_id
    AND professional_id = v_professional.id
    AND revoked_at IS NULL;

  IF FOUND THEN
    RETURN v_assignment_id;
  END IF;

  IF _sf_professional_busy(
       v_tenant_id, v_professional.id,
       v_appointment.scheduled_start, v_appointment.scheduled_end,
       p_appointment_id
     ) THEN
    RAISE EXCEPTION 'Este profissional ja possui atendimento neste periodo.'
      USING ERRCODE = 'check_violation';
  END IF;

  UPDATE appointment_assignments
  SET revoked_at = NULL, assigned_at = now(), assigned_by = auth.uid()
  WHERE appointment_id = p_appointment_id
    AND professional_id = v_professional.id
  RETURNING id INTO v_assignment_id;

  IF v_assignment_id IS NULL THEN
    INSERT INTO appointment_assignments (
      appointment_id, technician_user_id, professional_id
    )
    VALUES (
      p_appointment_id, v_professional.linked_user_id, v_professional.id
    )
    RETURNING id INTO v_assignment_id;
  END IF;

  INSERT INTO appointment_events (
    tenant_id, appointment_id, event_type, kind, reference_id, customer_id,
    technician_user_id, new_status, new_start, created_by
  ) VALUES (
    v_tenant_id, p_appointment_id, 'technician_added', v_appointment.kind,
    v_appointment.reference_id, v_appointment.customer_id,
    v_professional.linked_user_id, v_appointment.status,
    v_appointment.scheduled_start, auth.uid()
  );

  PERFORM log_audit(
    v_tenant_id,
    'appointment.technician_added',
    'appointments',
    p_appointment_id::text,
    NULL,
    jsonb_build_object('professional_id', v_professional.id)
  );

  RETURN v_assignment_id;
END;
$$;

CREATE OR REPLACE FUNCTION unassign_technician(
  p_appointment_id uuid,
  p_technician_user_id uuid DEFAULT NULL,
  p_professional_id uuid DEFAULT NULL
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_appointment appointments%ROWTYPE;
  v_professional_id uuid;
  v_remaining int;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'Nenhuma membership ativa encontrada.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF NOT has_permission('appointments.write') THEN
    RAISE EXCEPTION 'Permissao insuficiente para remover profissional.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_appointment
  FROM appointments
  WHERE id = p_appointment_id AND tenant_id = v_tenant_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Agendamento nao encontrado.'
      USING ERRCODE = 'no_data_found';
  END IF;

  v_professional_id := p_professional_id;
  IF v_professional_id IS NULL AND p_technician_user_id IS NOT NULL THEN
    SELECT id INTO v_professional_id
    FROM service_professionals
    WHERE linked_user_id = p_technician_user_id AND tenant_id = v_tenant_id;
  END IF;

  SELECT COUNT(*) INTO v_remaining
  FROM appointment_assignments
  WHERE appointment_id = p_appointment_id AND revoked_at IS NULL;

  IF v_remaining <= 1 THEN
    RAISE EXCEPTION 'O atendimento precisa de ao menos um profissional. Cancele o atendimento para liberar o horario.'
      USING ERRCODE = 'check_violation';
  END IF;

  UPDATE appointment_assignments
  SET revoked_at = now()
  WHERE appointment_id = p_appointment_id
    AND professional_id = v_professional_id
    AND revoked_at IS NULL;

  IF NOT FOUND THEN
    RETURN;
  END IF;

  INSERT INTO appointment_events (
    tenant_id, appointment_id, event_type, kind, reference_id, customer_id,
    technician_user_id, new_status, new_start, created_by
  ) VALUES (
    v_tenant_id, p_appointment_id, 'technician_removed', v_appointment.kind,
    v_appointment.reference_id, v_appointment.customer_id,
    p_technician_user_id, v_appointment.status,
    v_appointment.scheduled_start, auth.uid()
  );

  PERFORM log_audit(
    v_tenant_id,
    'appointment.technician_removed',
    'appointments',
    p_appointment_id::text,
    jsonb_build_object('professional_id', v_professional_id),
    NULL
  );
END;
$$;

-- ── 5. cancel_appointment: parceiro sem login nao cancela sozinho ───────────
-- A checagem por auth.uid() continua valendo para quem tem login. Parceiro
-- sem usuario nao acessa o app, entao o cancelamento dele passa pelo operador.

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

  UPDATE appointments SET status = 'cancelled' WHERE id = p_appointment_id;

  UPDATE appointment_assignments
  SET revoked_at = now()
  WHERE appointment_id = p_appointment_id AND revoked_at IS NULL;

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

GRANT EXECUTE ON FUNCTION schedule_appointment(text, uuid, uuid, uuid, timestamptz, timestamptz, uuid, text, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION assign_technician(uuid, uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION unassign_technician(uuid, uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION cancel_appointment(uuid, text) TO authenticated;

-- CREATE OR REPLACE so substitui quando a assinatura e identica: acrescentar
-- um parametro cria um overload novo e deixa o antigo vivo. Com os dois no
-- catalogo, uma chamada com os argumentos antigos fica ambigua e o PostgREST
-- devolve PGRST203. As versoes anteriores saem daqui.
DROP FUNCTION IF EXISTS assign_technician(uuid, uuid);
DROP FUNCTION IF EXISTS unassign_technician(uuid, uuid);
DROP FUNCTION IF EXISTS schedule_appointment(
  text, uuid, uuid, uuid, timestamptz, timestamptz, uuid, text
);

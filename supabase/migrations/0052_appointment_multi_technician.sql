-- =============================================================================
-- Migration: 0052_appointment_multi_technician
-- Descricao: Mais de um profissional no mesmo atendimento — F5-P2 (ADR-027)
-- Depende de: 0004_scheduling, 0051_appointment_events
-- Rollback: supabase/rollbacks/0052_appointment_multi_technician_rollback.sql
--
-- ORIGEM: servico que precisa de dupla (troca de compressor, quadro trifasico,
-- mudanca de bancada) hoje so consegue um tecnico na agenda, porque
-- `schedule_appointment` insere exatamente um `appointment_assignments` e nao
-- existe caminho para acrescentar outro depois. O schema ja e 1:N desde a
-- 0004 — falta so a porta de entrada.
--
-- MODELO: `assign_technician` acrescenta, `unassign_technician` revoga
-- (soft, via `revoked_at`, preservando quem esteve no atendimento). O
-- profissional adicional pode ser de outra categoria: um servico pode exigir
-- eletricista + ajudante. A validacao de conflito de horario e a mesma do
-- agendamento, para nao colocar ninguem em dois lugares ao mesmo tempo.
--
-- ponytail: sem papel por atribuicao (titular/auxiliar). Todos os atribuidos
-- sao iguais; o primeiro (`assigned_at` mais antigo) e usado como "o tecnico"
-- onde a UI precisa de um so. Adicionar papel quando houver regra real que
-- dependa disso — comissao diferente por papel, por exemplo.
-- =============================================================================

-- Novos tipos de evento no historico da agenda.
ALTER TABLE appointment_events
  DROP CONSTRAINT IF EXISTS appointment_events_event_type_check;

ALTER TABLE appointment_events
  ADD CONSTRAINT appointment_events_event_type_check
  CHECK (event_type IN (
    'scheduled','rescheduled','cancelled','status_changed',
    'technician_added','technician_removed'
  ));

-- ── assign_technician ───────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION assign_technician(
  p_appointment_id uuid,
  p_technician_user_id uuid
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id  uuid;
  v_appointment appointments%ROWTYPE;
  v_is_technician boolean;
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

  -- Ja esta neste atendimento: idempotente, so devolve o assignment.
  SELECT id INTO v_assignment_id
  FROM appointment_assignments
  WHERE appointment_id = p_appointment_id
    AND technician_user_id = p_technician_user_id
    AND revoked_at IS NULL;

  IF FOUND THEN
    RETURN v_assignment_id;
  END IF;

  IF EXISTS (
    SELECT 1
    FROM appointment_assignments aa
    JOIN appointments a ON a.id = aa.appointment_id
    WHERE aa.tenant_id = v_tenant_id
      AND aa.technician_user_id = p_technician_user_id
      AND aa.revoked_at IS NULL
      AND a.id <> p_appointment_id
      AND a.status NOT IN ('cancelled','no_show')
      AND tstzrange(a.scheduled_start, a.scheduled_end, '[)') &&
          tstzrange(v_appointment.scheduled_start, v_appointment.scheduled_end, '[)')
  ) THEN
    RAISE EXCEPTION 'Este tecnico ja possui atendimento neste periodo.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- A constraint uq_appointment_active_technician e por (appointment_id,
  -- technician_user_id) sem filtro de revoked_at, entao reatribuir alguem que
  -- ja saiu do atendimento e um UPDATE, nao um INSERT.
  UPDATE appointment_assignments
  SET revoked_at = NULL, assigned_at = now(), assigned_by = auth.uid()
  WHERE appointment_id = p_appointment_id
    AND technician_user_id = p_technician_user_id
  RETURNING id INTO v_assignment_id;

  IF v_assignment_id IS NULL THEN
    INSERT INTO appointment_assignments (appointment_id, technician_user_id)
    VALUES (p_appointment_id, p_technician_user_id)
    RETURNING id INTO v_assignment_id;
  END IF;

  INSERT INTO appointment_events (
    tenant_id, appointment_id, event_type, kind, reference_id, customer_id,
    technician_user_id, new_status, new_start, created_by
  ) VALUES (
    v_tenant_id, p_appointment_id, 'technician_added', v_appointment.kind,
    v_appointment.reference_id, v_appointment.customer_id,
    p_technician_user_id, v_appointment.status,
    v_appointment.scheduled_start, auth.uid()
  );

  PERFORM log_audit(
    v_tenant_id,
    'appointment.technician_added',
    'appointments',
    p_appointment_id::text,
    NULL,
    jsonb_build_object('technician_user_id', p_technician_user_id)
  );

  RETURN v_assignment_id;
END;
$$;

-- ── unassign_technician ─────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION unassign_technician(
  p_appointment_id uuid,
  p_technician_user_id uuid
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_appointment appointments%ROWTYPE;
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

  SELECT COUNT(*) INTO v_remaining
  FROM appointment_assignments
  WHERE appointment_id = p_appointment_id AND revoked_at IS NULL;

  -- Atendimento sem ninguem seria um fantasma na agenda: fica ocupando o
  -- horario sem responsavel, e o item nao volta para a fila porque o
  -- appointment continua ativo. Para esvaziar, cancele o atendimento.
  IF v_remaining <= 1 THEN
    RAISE EXCEPTION 'O atendimento precisa de ao menos um profissional. Cancele o atendimento para liberar o horario.'
      USING ERRCODE = 'check_violation';
  END IF;

  UPDATE appointment_assignments
  SET revoked_at = now()
  WHERE appointment_id = p_appointment_id
    AND technician_user_id = p_technician_user_id
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
    jsonb_build_object('technician_user_id', p_technician_user_id),
    NULL
  );
END;
$$;

GRANT EXECUTE ON FUNCTION assign_technician(uuid, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION unassign_technician(uuid, uuid) TO authenticated;

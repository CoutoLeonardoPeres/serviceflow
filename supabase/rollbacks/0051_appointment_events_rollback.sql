-- Rollback: 0051_appointment_events
--
-- PERDA DE DADOS: derruba `appointment_events`. O historico de agendamento,
-- cancelamento e reagendamento e perdido. Exporte antes se houver relatorio
-- dependendo dele:
--   COPY (SELECT * FROM appointment_events) TO '/tmp/appointment_events.csv' CSV HEADER;
--
-- ATENCAO: restaurar a FK de `reference_id` falha se ja existir agendamento
-- de ordem de servico, porque o id da OS nao existe em `service_requests`.
-- Cancele/apague esses agendamentos antes, ou mantenha a FK fora.

DROP TRIGGER IF EXISTS trg_appointments_events ON appointments;
DROP FUNCTION IF EXISTS _sf_log_appointment_event();
DROP FUNCTION IF EXISTS cancel_appointment(uuid, text);
DROP TABLE IF EXISTS appointment_events;

-- Volta o trigger de meta para a versao da 0004 (sem o ramo de work_order).
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

-- Volta schedule_appointment para a versao da 0004 (so 'visit').
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

  IF p_kind <> 'visit' THEN
    RAISE EXCEPTION 'Tipo de agendamento ainda nao suportado no MVP: %', p_kind
      USING ERRCODE = 'check_violation';
  END IF;

  IF p_scheduled_end <= p_scheduled_start THEN
    RAISE EXCEPTION 'Periodo de agendamento invalido.'
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

-- FK original (so aplica se nao houver agendamento de OS — ver aviso acima):
-- ALTER TABLE appointments
--   ADD CONSTRAINT appointments_reference_id_fkey
--   FOREIGN KEY (reference_id) REFERENCES service_requests(id);

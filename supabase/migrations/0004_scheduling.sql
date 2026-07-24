-- =============================================================================
-- Migration: 0004_scheduling
-- Descricao: Agenda, atribuicoes e visitas tecnicas — Entrega 5
-- Depende de: 0001_foundation, 0002_customers, 0003_service_requests
-- Rollback: supabase/rollbacks/0004_scheduling_rollback.sql
-- =============================================================================

CREATE TABLE appointments (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  kind            text        NOT NULL CHECK (kind IN ('visit','work_order')),
  reference_id    uuid        NOT NULL REFERENCES service_requests(id),
  customer_id     uuid        NOT NULL REFERENCES customers(id),
  address_id      uuid        REFERENCES customer_addresses(id),
  scheduled_start timestamptz NOT NULL,
  scheduled_end   timestamptz NOT NULL,
  status          text        NOT NULL DEFAULT 'scheduled'
                              CHECK (status IN ('scheduled','confirmed','done','cancelled','no_show')),
  notes           text        CHECK (notes IS NULL OR char_length(notes) <= 1000),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  created_by      uuid        REFERENCES auth.users(id),
  updated_by      uuid        REFERENCES auth.users(id),
  CONSTRAINT chk_appointments_period CHECK (scheduled_end > scheduled_start)
);

CREATE INDEX idx_appointments_tenant_start ON appointments (tenant_id, scheduled_start);
CREATE INDEX idx_appointments_tenant_status ON appointments (tenant_id, status);
CREATE INDEX idx_appointments_reference ON appointments (tenant_id, kind, reference_id);
CREATE INDEX idx_appointments_customer ON appointments (tenant_id, customer_id);

CREATE TABLE appointment_assignments (
  id                 uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id          uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  appointment_id     uuid        NOT NULL REFERENCES appointments(id) ON DELETE CASCADE,
  technician_user_id uuid        NOT NULL REFERENCES profiles(id),
  assigned_at        timestamptz NOT NULL DEFAULT now(),
  assigned_by        uuid        REFERENCES auth.users(id),
  revoked_at         timestamptz,
  CONSTRAINT uq_appointment_active_technician UNIQUE (appointment_id, technician_user_id)
);

CREATE INDEX idx_appointment_assignments_tenant_technician
  ON appointment_assignments (tenant_id, technician_user_id)
  WHERE revoked_at IS NULL;
CREATE INDEX idx_appointment_assignments_appointment
  ON appointment_assignments (appointment_id);

CREATE TABLE technical_visits (
  id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  request_id     uuid        NOT NULL REFERENCES service_requests(id),
  appointment_id uuid        NOT NULL UNIQUE REFERENCES appointments(id) ON DELETE CASCADE,
  technician_id  uuid        REFERENCES profiles(id),
  diagnosis      text        CHECK (diagnosis IS NULL OR char_length(diagnosis) <= 5000),
  executed_at    timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  created_by     uuid        REFERENCES auth.users(id),
  updated_by     uuid        REFERENCES auth.users(id)
);

CREATE INDEX idx_technical_visits_tenant_request ON technical_visits (tenant_id, request_id);
CREATE INDEX idx_technical_visits_technician ON technical_visits (tenant_id, technician_id);

CREATE TABLE visit_evidence (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  visit_id     uuid        NOT NULL REFERENCES technical_visits(id) ON DELETE CASCADE,
  storage_path text        NOT NULL CHECK (char_length(storage_path) BETWEEN 10 AND 700),
  kind         text        NOT NULL CHECK (kind IN ('photo','video','document')),
  checksum     text        CHECK (checksum IS NULL OR char_length(checksum) BETWEEN 32 AND 128),
  created_at   timestamptz NOT NULL DEFAULT now(),
  created_by   uuid        REFERENCES auth.users(id)
);

CREATE INDEX idx_visit_evidence_visit ON visit_evidence (visit_id, created_at DESC);

CREATE TRIGGER trg_appointments_updated_at
  BEFORE UPDATE ON appointments
  FOR EACH ROW EXECUTE FUNCTION _sf_update_updated_at();

CREATE TRIGGER trg_technical_visits_updated_at
  BEFORE UPDATE ON technical_visits
  FOR EACH ROW EXECUTE FUNCTION _sf_update_updated_at();

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

CREATE TRIGGER trg_appointments_meta
  BEFORE INSERT OR UPDATE ON appointments
  FOR EACH ROW EXECUTE FUNCTION _sf_set_appointment_meta();

CREATE OR REPLACE FUNCTION _sf_set_appointment_assignment_meta()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  SELECT tenant_id INTO NEW.tenant_id
  FROM appointments
  WHERE id = NEW.appointment_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Agendamento nao encontrado ou sem acesso: %', NEW.appointment_id
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.assigned_by := auth.uid();
  ELSE
    NEW.tenant_id := OLD.tenant_id;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_appointment_assignments_meta
  BEFORE INSERT OR UPDATE ON appointment_assignments
  FOR EACH ROW EXECUTE FUNCTION _sf_set_appointment_assignment_meta();

CREATE OR REPLACE FUNCTION _sf_set_technical_visit_meta()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  SELECT tenant_id INTO NEW.tenant_id
  FROM appointments
  WHERE id = NEW.appointment_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Agendamento nao encontrado ou sem acesso: %', NEW.appointment_id
      USING ERRCODE = 'insufficient_privilege';
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

CREATE TRIGGER trg_technical_visits_meta
  BEFORE INSERT OR UPDATE ON technical_visits
  FOR EACH ROW EXECUTE FUNCTION _sf_set_technical_visit_meta();

CREATE OR REPLACE FUNCTION _sf_set_visit_evidence_meta()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  SELECT tenant_id INTO NEW.tenant_id
  FROM technical_visits
  WHERE id = NEW.visit_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Visita nao encontrada ou sem acesso: %', NEW.visit_id
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.created_by := auth.uid();
  ELSE
    NEW.tenant_id := OLD.tenant_id;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_visit_evidence_meta
  BEFORE INSERT OR UPDATE ON visit_evidence
  FOR EACH ROW EXECUTE FUNCTION _sf_set_visit_evidence_meta();

CREATE OR REPLACE FUNCTION list_tenant_technicians()
RETURNS TABLE(user_id uuid, name text, email text, phone text)
LANGUAGE sql SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    tm.user_id,
    COALESCE(p.full_name, 'Tecnico') AS name,
    NULL::text AS email,
    p.phone
  FROM tenant_memberships tm
  JOIN roles r ON r.id = tm.role_id
  LEFT JOIN profiles p ON p.id = tm.user_id
  WHERE tm.tenant_id = current_tenant_id()
    AND tm.status = 'active'
    AND r.key = 'technician'
    AND has_permission('appointments.read')
  ORDER BY p.full_name NULLS LAST;
$$;

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

ALTER TABLE appointments ENABLE ROW LEVEL SECURITY;
ALTER TABLE appointment_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE technical_visits ENABLE ROW LEVEL SECURITY;
ALTER TABLE visit_evidence ENABLE ROW LEVEL SECURITY;

CREATE POLICY "appointments_select" ON appointments
  FOR SELECT TO authenticated
  USING (tenant_id = current_tenant_id() AND has_permission('appointments.read'));

CREATE POLICY "appointments_insert" ON appointments
  FOR INSERT TO authenticated
  WITH CHECK (has_permission('appointments.write'));

CREATE POLICY "appointments_update" ON appointments
  FOR UPDATE TO authenticated
  USING (tenant_id = current_tenant_id() AND has_permission('appointments.write'))
  WITH CHECK (tenant_id = current_tenant_id() AND has_permission('appointments.write'));

CREATE POLICY "appointment_assignments_select" ON appointment_assignments
  FOR SELECT TO authenticated
  USING (tenant_id = current_tenant_id() AND has_permission('appointments.read'));

CREATE POLICY "appointment_assignments_insert" ON appointment_assignments
  FOR INSERT TO authenticated
  WITH CHECK (has_permission('appointments.write'));

CREATE POLICY "appointment_assignments_update" ON appointment_assignments
  FOR UPDATE TO authenticated
  USING (tenant_id = current_tenant_id() AND has_permission('appointments.write'))
  WITH CHECK (tenant_id = current_tenant_id() AND has_permission('appointments.write'));

CREATE POLICY "technical_visits_select" ON technical_visits
  FOR SELECT TO authenticated
  USING (tenant_id = current_tenant_id() AND has_permission('appointments.read'));

CREATE POLICY "technical_visits_insert" ON technical_visits
  FOR INSERT TO authenticated
  WITH CHECK (has_permission('appointments.write'));

CREATE POLICY "technical_visits_update" ON technical_visits
  FOR UPDATE TO authenticated
  USING (tenant_id = current_tenant_id() AND has_permission('appointments.write'))
  WITH CHECK (tenant_id = current_tenant_id() AND has_permission('appointments.write'));

CREATE POLICY "visit_evidence_select" ON visit_evidence
  FOR SELECT TO authenticated
  USING (tenant_id = current_tenant_id() AND has_permission('appointments.read'));

CREATE POLICY "visit_evidence_insert" ON visit_evidence
  FOR INSERT TO authenticated
  WITH CHECK (has_permission('appointments.write'));

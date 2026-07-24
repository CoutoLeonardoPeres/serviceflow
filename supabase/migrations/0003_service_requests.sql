-- =============================================================================
-- Migration: 0003_service_requests
-- Descricao: Chamados, categorias, prioridades, historico, anexos e atribuicoes
-- Depende de: 0001_foundation, 0002_customers
-- Rollback: 0003_service_requests_rollback.sql
-- =============================================================================

CREATE TABLE service_categories (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name        text        NOT NULL CHECK (char_length(name) BETWEEN 2 AND 120),
  description text        CHECK (description IS NULL OR char_length(description) <= 500),
  is_active   boolean     NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  created_by  uuid        REFERENCES auth.users(id)
);

CREATE UNIQUE INDEX uq_service_categories_tenant_name
  ON service_categories (tenant_id, lower(name));
CREATE INDEX idx_service_categories_tenant_active
  ON service_categories (tenant_id, is_active);

CREATE TABLE service_priorities (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name        text        NOT NULL CHECK (char_length(name) BETWEEN 2 AND 80),
  level       integer     NOT NULL CHECK (level BETWEEN 1 AND 5),
  sla_hours   integer     CHECK (sla_hours IS NULL OR sla_hours > 0),
  is_active   boolean     NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  created_by  uuid        REFERENCES auth.users(id)
);

CREATE UNIQUE INDEX uq_service_priorities_tenant_name
  ON service_priorities (tenant_id, lower(name));
CREATE UNIQUE INDEX uq_service_priorities_tenant_level
  ON service_priorities (tenant_id, level);
CREATE INDEX idx_service_priorities_tenant_active
  ON service_priorities (tenant_id, is_active);

CREATE TABLE service_requests (
  id                   uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id            uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  number               bigint      NOT NULL,
  customer_id          uuid        NOT NULL REFERENCES customers(id),
  requester_contact_id uuid        REFERENCES customer_contacts(id),
  address_id           uuid        REFERENCES customer_addresses(id),
  category_id          uuid        REFERENCES service_categories(id),
  priority_id          uuid        REFERENCES service_priorities(id),
  title                text        NOT NULL CHECK (char_length(title) BETWEEN 3 AND 160),
  description          text        NOT NULL CHECK (char_length(description) BETWEEN 10 AND 5000),
  availability_notes   text        CHECK (availability_notes IS NULL OR char_length(availability_notes) <= 1000),
  channel              text        NOT NULL CHECK (channel IN ('phone','whatsapp','email','form','in_person')),
  status               text        NOT NULL DEFAULT 'opened'
                                      CHECK (status IN (
                                        'draft','opened','triage','awaiting_customer',
                                        'scheduled','converted_to_quote',
                                        'converted_to_work_order','cancelled','closed'
                                      )),
  assigned_to          uuid        REFERENCES auth.users(id),
  created_at           timestamptz NOT NULL DEFAULT now(),
  updated_at           timestamptz NOT NULL DEFAULT now(),
  created_by           uuid        REFERENCES auth.users(id),
  updated_by           uuid        REFERENCES auth.users(id)
);

CREATE UNIQUE INDEX uq_service_requests_tenant_number
  ON service_requests (tenant_id, number);
CREATE INDEX idx_service_requests_tenant_status
  ON service_requests (tenant_id, status);
CREATE INDEX idx_service_requests_customer
  ON service_requests (tenant_id, customer_id);
CREATE INDEX idx_service_requests_category
  ON service_requests (tenant_id, category_id);
CREATE INDEX idx_service_requests_priority
  ON service_requests (tenant_id, priority_id);
CREATE INDEX idx_service_requests_assigned
  ON service_requests (tenant_id, assigned_to);
CREATE INDEX idx_service_requests_created
  ON service_requests (tenant_id, created_at DESC);
CREATE INDEX idx_service_requests_title
  ON service_requests (tenant_id, title text_pattern_ops);

CREATE TABLE service_request_status_history (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  request_id  uuid        NOT NULL REFERENCES service_requests(id) ON DELETE CASCADE,
  from_status text,
  to_status   text        NOT NULL,
  actor_id    uuid        REFERENCES auth.users(id),
  reason      text        CHECK (reason IS NULL OR char_length(reason) <= 500),
  created_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_service_request_status_history_request
  ON service_request_status_history (request_id, created_at DESC);
CREATE INDEX idx_service_request_status_history_tenant
  ON service_request_status_history (tenant_id, created_at DESC);

CREATE TABLE service_request_attachments (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  request_id   uuid        NOT NULL REFERENCES service_requests(id) ON DELETE CASCADE,
  storage_path text        NOT NULL CHECK (char_length(storage_path) BETWEEN 10 AND 700),
  mime_type    text        NOT NULL CHECK (
                              mime_type IN (
                                'image/jpeg','image/png','image/webp',
                                'video/mp4','application/pdf'
                              )
                            ),
  size_bytes   bigint      NOT NULL CHECK (size_bytes > 0 AND size_bytes <= 52428800),
  checksum     text        CHECK (checksum IS NULL OR char_length(checksum) BETWEEN 32 AND 128),
  created_at   timestamptz NOT NULL DEFAULT now(),
  uploaded_by  uuid        REFERENCES auth.users(id)
);

CREATE UNIQUE INDEX uq_service_request_attachments_path
  ON service_request_attachments (storage_path);
CREATE INDEX idx_service_request_attachments_request
  ON service_request_attachments (request_id, created_at DESC);

CREATE TABLE service_request_notes (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  request_id  uuid        NOT NULL REFERENCES service_requests(id) ON DELETE CASCADE,
  body        text        NOT NULL CHECK (char_length(body) BETWEEN 1 AND 2000),
  is_internal boolean     NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  created_by  uuid        REFERENCES auth.users(id)
);

CREATE INDEX idx_service_request_notes_request
  ON service_request_notes (request_id, created_at DESC);

CREATE TABLE service_request_assignments (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  request_id  uuid        NOT NULL REFERENCES service_requests(id) ON DELETE CASCADE,
  user_id     uuid        NOT NULL REFERENCES auth.users(id),
  role        text        NOT NULL DEFAULT 'responsavel'
                          CHECK (char_length(role) BETWEEN 2 AND 80),
  assigned_at timestamptz NOT NULL DEFAULT now(),
  assigned_by uuid        REFERENCES auth.users(id),
  revoked_at  timestamptz
);

CREATE INDEX idx_service_request_assignments_request
  ON service_request_assignments (request_id);
CREATE INDEX idx_service_request_assignments_user
  ON service_request_assignments (tenant_id, user_id)
  WHERE revoked_at IS NULL;

CREATE TRIGGER trg_service_categories_updated_at
  BEFORE UPDATE ON service_categories
  FOR EACH ROW EXECUTE FUNCTION _sf_update_updated_at();

CREATE TRIGGER trg_service_priorities_updated_at
  BEFORE UPDATE ON service_priorities
  FOR EACH ROW EXECUTE FUNCTION _sf_update_updated_at();

CREATE TRIGGER trg_service_requests_updated_at
  BEFORE UPDATE ON service_requests
  FOR EACH ROW EXECUTE FUNCTION _sf_update_updated_at();

CREATE OR REPLACE FUNCTION _sf_set_service_catalog_meta()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF auth.uid() IS NULL THEN
    IF NEW.tenant_id IS NULL THEN
      RAISE EXCEPTION 'tenant_id e obrigatorio em seed/operacao administrativa.';
    END IF;
  ELSE
    NEW.tenant_id := current_tenant_id();
  END IF;

  IF NEW.tenant_id IS NULL THEN
    RAISE EXCEPTION 'Nenhuma membership ativa encontrada.'
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

CREATE TRIGGER trg_service_categories_meta
  BEFORE INSERT OR UPDATE ON service_categories
  FOR EACH ROW EXECUTE FUNCTION _sf_set_service_catalog_meta();

CREATE TRIGGER trg_service_priorities_meta
  BEFORE INSERT OR UPDATE ON service_priorities
  FOR EACH ROW EXECUTE FUNCTION _sf_set_service_catalog_meta();

CREATE OR REPLACE FUNCTION _sf_set_service_request_meta()
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

  IF NEW.tenant_id IS NULL THEN
    RAISE EXCEPTION 'Nenhuma membership ativa encontrada.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT tenant_id INTO v_tenant_id FROM customers WHERE id = NEW.customer_id;
  IF v_tenant_id IS NULL OR v_tenant_id <> NEW.tenant_id THEN
    RAISE EXCEPTION 'Cliente inexistente ou fora do tenant autorizado.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF NEW.requester_contact_id IS NOT NULL THEN
    SELECT tenant_id INTO v_tenant_id FROM customer_contacts WHERE id = NEW.requester_contact_id;
    IF v_tenant_id IS NULL OR v_tenant_id <> NEW.tenant_id THEN
      RAISE EXCEPTION 'Contato fora do tenant autorizado.'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  IF NEW.address_id IS NOT NULL THEN
    SELECT tenant_id INTO v_tenant_id FROM customer_addresses WHERE id = NEW.address_id;
    IF v_tenant_id IS NULL OR v_tenant_id <> NEW.tenant_id THEN
      RAISE EXCEPTION 'Endereco fora do tenant autorizado.'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  IF NEW.category_id IS NOT NULL THEN
    SELECT tenant_id INTO v_tenant_id FROM service_categories WHERE id = NEW.category_id;
    IF v_tenant_id IS NULL OR v_tenant_id <> NEW.tenant_id THEN
      RAISE EXCEPTION 'Categoria fora do tenant autorizado.'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  IF NEW.priority_id IS NOT NULL THEN
    SELECT tenant_id INTO v_tenant_id FROM service_priorities WHERE id = NEW.priority_id;
    IF v_tenant_id IS NULL OR v_tenant_id <> NEW.tenant_id THEN
      RAISE EXCEPTION 'Prioridade fora do tenant autorizado.'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF NEW.number IS NULL OR NEW.number = 0 THEN
      NEW.number := next_sequence(NEW.tenant_id, 'service_request');
    END IF;
    NEW.created_by := auth.uid();
    NEW.updated_by := auth.uid();
  ELSE
    NEW.tenant_id := OLD.tenant_id;
    NEW.number := OLD.number;
    NEW.updated_by := auth.uid();
    IF OLD.status <> NEW.status
      AND current_setting('app.allow_service_request_status_update', true) <> 'true' THEN
      RAISE EXCEPTION 'Status de chamado deve ser alterado pela funcao de transicao.'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_service_requests_meta
  BEFORE INSERT OR UPDATE ON service_requests
  FOR EACH ROW EXECUTE FUNCTION _sf_set_service_request_meta();

CREATE OR REPLACE FUNCTION _sf_set_service_request_child_meta()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  SELECT tenant_id INTO NEW.tenant_id
  FROM service_requests
  WHERE id = NEW.request_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Chamado nao encontrado ou sem acesso: %', NEW.request_id
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF TG_OP = 'INSERT' THEN
    IF TG_TABLE_NAME = 'service_request_attachments' THEN
      NEW.uploaded_by := auth.uid();
    ELSIF TG_TABLE_NAME = 'service_request_assignments' THEN
      NEW.assigned_by := auth.uid();
    ELSE
      NEW.created_by := auth.uid();
    END IF;
  ELSE
    NEW.tenant_id := OLD.tenant_id;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_service_request_attachments_meta
  BEFORE INSERT OR UPDATE ON service_request_attachments
  FOR EACH ROW EXECUTE FUNCTION _sf_set_service_request_child_meta();

CREATE TRIGGER trg_service_request_notes_meta
  BEFORE INSERT OR UPDATE ON service_request_notes
  FOR EACH ROW EXECUTE FUNCTION _sf_set_service_request_child_meta();

CREATE TRIGGER trg_service_request_assignments_meta
  BEFORE INSERT OR UPDATE ON service_request_assignments
  FOR EACH ROW EXECUTE FUNCTION _sf_set_service_request_child_meta();

CREATE OR REPLACE FUNCTION _sf_record_service_request_status_history()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    INSERT INTO service_request_status_history (
      tenant_id, request_id, from_status, to_status, actor_id, reason
    ) VALUES (
      NEW.tenant_id, NEW.id, NULL, NEW.status, auth.uid(), 'created'
    );
  ELSIF OLD.status <> NEW.status THEN
    INSERT INTO service_request_status_history (
      tenant_id, request_id, from_status, to_status, actor_id, reason
    ) VALUES (
      NEW.tenant_id,
      NEW.id,
      OLD.status,
      NEW.status,
      auth.uid(),
      current_setting('app.service_request_status_reason', true)
    );
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_service_requests_status_history
  AFTER INSERT OR UPDATE OF status ON service_requests
  FOR EACH ROW EXECUTE FUNCTION _sf_record_service_request_status_history();

CREATE OR REPLACE FUNCTION _sf_audit_service_request_change()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM log_audit(
      NEW.tenant_id,
      'service_request.created',
      'service_requests',
      NEW.id::text,
      NULL,
      jsonb_build_object(
        'number', NEW.number,
        'title', NEW.title,
        'status', NEW.status,
        'customer_id', NEW.customer_id
      )
    );
  ELSIF TG_OP = 'UPDATE' THEN
    PERFORM log_audit(
      NEW.tenant_id,
      'service_request.updated',
      'service_requests',
      NEW.id::text,
      jsonb_build_object(
        'title', OLD.title,
        'status', OLD.status,
        'assigned_to', OLD.assigned_to
      ),
      jsonb_build_object(
        'title', NEW.title,
        'status', NEW.status,
        'assigned_to', NEW.assigned_to
      )
    );
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_service_requests_audit
  AFTER INSERT OR UPDATE ON service_requests
  FOR EACH ROW EXECUTE FUNCTION _sf_audit_service_request_change();

CREATE OR REPLACE FUNCTION transition_service_request(
  p_request_id uuid,
  p_to_status text,
  p_reason text DEFAULT NULL
) RETURNS service_requests LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current service_requests;
  v_allowed boolean;
BEGIN
  SELECT * INTO v_current
  FROM service_requests
  WHERE id = p_request_id
    AND tenant_id = current_tenant_id()
  FOR UPDATE;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Chamado nao encontrado.'
      USING ERRCODE = 'no_data_found';
  END IF;

  IF NOT has_permission('service_requests.manage') THEN
    RAISE EXCEPTION 'Permissao insuficiente para alterar status.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_allowed := CASE
    WHEN v_current.status = p_to_status THEN true
    WHEN p_to_status = 'cancelled' AND v_current.status NOT IN ('cancelled','closed') THEN true
    WHEN v_current.status = 'draft' AND p_to_status = 'opened' THEN true
    WHEN v_current.status = 'opened' AND p_to_status = 'triage' THEN true
    WHEN v_current.status = 'triage' AND p_to_status IN ('awaiting_customer','scheduled','converted_to_quote','converted_to_work_order','closed') THEN true
    WHEN v_current.status = 'awaiting_customer' AND p_to_status = 'triage' THEN true
    WHEN v_current.status = 'scheduled' AND p_to_status IN ('converted_to_quote','converted_to_work_order','closed') THEN true
    ELSE false
  END;

  IF NOT v_allowed THEN
    RAISE EXCEPTION 'Transicao de status invalida: % -> %', v_current.status, p_to_status
      USING ERRCODE = 'check_violation';
  END IF;

  PERFORM set_config('app.allow_service_request_status_update', 'true', true);
  PERFORM set_config('app.service_request_status_reason', COALESCE(p_reason, ''), true);

  UPDATE service_requests
  SET status = p_to_status
  WHERE id = p_request_id
  RETURNING * INTO v_current;

  RETURN v_current;
END;
$$;

ALTER TABLE service_categories ENABLE ROW LEVEL SECURITY;
ALTER TABLE service_priorities ENABLE ROW LEVEL SECURITY;
ALTER TABLE service_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE service_request_status_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE service_request_attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE service_request_notes ENABLE ROW LEVEL SECURITY;
ALTER TABLE service_request_assignments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "service_categories_select" ON service_categories
  FOR SELECT TO authenticated
  USING (tenant_id = current_tenant_id() AND has_permission('service_requests.read'));
CREATE POLICY "service_categories_insert" ON service_categories
  FOR INSERT TO authenticated
  WITH CHECK (has_permission('service_requests.manage'));
CREATE POLICY "service_categories_update" ON service_categories
  FOR UPDATE TO authenticated
  USING (tenant_id = current_tenant_id() AND has_permission('service_requests.manage'))
  WITH CHECK (tenant_id = current_tenant_id() AND has_permission('service_requests.manage'));

CREATE POLICY "service_priorities_select" ON service_priorities
  FOR SELECT TO authenticated
  USING (tenant_id = current_tenant_id() AND has_permission('service_requests.read'));
CREATE POLICY "service_priorities_insert" ON service_priorities
  FOR INSERT TO authenticated
  WITH CHECK (has_permission('service_requests.manage'));
CREATE POLICY "service_priorities_update" ON service_priorities
  FOR UPDATE TO authenticated
  USING (tenant_id = current_tenant_id() AND has_permission('service_requests.manage'))
  WITH CHECK (tenant_id = current_tenant_id() AND has_permission('service_requests.manage'));

CREATE POLICY "service_requests_select" ON service_requests
  FOR SELECT TO authenticated
  USING (tenant_id = current_tenant_id() AND has_permission('service_requests.read'));
CREATE POLICY "service_requests_insert" ON service_requests
  FOR INSERT TO authenticated
  WITH CHECK (has_permission('service_requests.write'));
CREATE POLICY "service_requests_update" ON service_requests
  FOR UPDATE TO authenticated
  USING (tenant_id = current_tenant_id() AND has_permission('service_requests.write'))
  WITH CHECK (tenant_id = current_tenant_id() AND has_permission('service_requests.write'));

CREATE POLICY "service_request_status_history_select" ON service_request_status_history
  FOR SELECT TO authenticated
  USING (tenant_id = current_tenant_id() AND has_permission('service_requests.read'));

CREATE POLICY "service_request_attachments_select" ON service_request_attachments
  FOR SELECT TO authenticated
  USING (tenant_id = current_tenant_id() AND has_permission('service_requests.read'));
CREATE POLICY "service_request_attachments_insert" ON service_request_attachments
  FOR INSERT TO authenticated
  WITH CHECK (has_permission('service_requests.write'));

CREATE POLICY "service_request_notes_select" ON service_request_notes
  FOR SELECT TO authenticated
  USING (tenant_id = current_tenant_id() AND has_permission('service_requests.read'));
CREATE POLICY "service_request_notes_insert" ON service_request_notes
  FOR INSERT TO authenticated
  WITH CHECK (has_permission('service_requests.write'));

CREATE POLICY "service_request_assignments_select" ON service_request_assignments
  FOR SELECT TO authenticated
  USING (tenant_id = current_tenant_id() AND has_permission('service_requests.read'));
CREATE POLICY "service_request_assignments_insert" ON service_request_assignments
  FOR INSERT TO authenticated
  WITH CHECK (has_permission('service_requests.manage'));
CREATE POLICY "service_request_assignments_update" ON service_request_assignments
  FOR UPDATE TO authenticated
  USING (tenant_id = current_tenant_id() AND has_permission('service_requests.manage'))
  WITH CHECK (tenant_id = current_tenant_id() AND has_permission('service_requests.manage'));

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'service-request-attachments',
  'service-request-attachments',
  false,
  52428800,
  ARRAY['image/jpeg','image/png','image/webp','video/mp4','application/pdf']
)
ON CONFLICT (id) DO NOTHING;

CREATE POLICY "service_request_storage_select" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'service-request-attachments'
    AND (storage.foldername(name))[1] = current_tenant_id()::text
    AND has_permission('service_requests.read')
  );

CREATE POLICY "service_request_storage_insert" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'service-request-attachments'
    AND (storage.foldername(name))[1] = current_tenant_id()::text
    AND has_permission('service_requests.write')
  );

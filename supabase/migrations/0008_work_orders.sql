-- =============================================================================
-- Migration: 0008_work_orders
-- Descricao: Ordens de servico, execucao e conversao de orcamento aprovado — Entrega 7
-- Depende de: 0001_foundation, 0002_customers, 0003_service_requests, 0005_quotations
-- Rollback: supabase/rollbacks/0008_work_orders_rollback.sql
-- =============================================================================

CREATE TABLE work_orders (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  number          bigint      NOT NULL,
  customer_id     uuid        NOT NULL REFERENCES customers(id),
  request_id      uuid        REFERENCES service_requests(id),
  quotation_id    uuid        REFERENCES quotations(id),
  address_id      uuid        REFERENCES customer_addresses(id),
  status          text        NOT NULL DEFAULT 'opened'
                                  CHECK (status IN (
                                    'draft','opened','scheduled','in_progress',
                                    'awaiting_customer','paused','done','cancelled'
                                  )),
  title           text        NOT NULL CHECK (char_length(title) BETWEEN 3 AND 180),
  description     text        NOT NULL CHECK (char_length(description) BETWEEN 3 AND 4000),
  total_cents     integer     NOT NULL DEFAULT 0 CHECK (total_cents >= 0),
  scheduled_start timestamptz,
  scheduled_end   timestamptz,
  completed_at    timestamptz,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  created_by      uuid        REFERENCES auth.users(id),
  updated_by      uuid        REFERENCES auth.users(id),
  CONSTRAINT chk_work_orders_schedule CHECK (
    scheduled_start IS NULL OR scheduled_end IS NULL OR scheduled_end > scheduled_start
  )
);

CREATE UNIQUE INDEX uq_work_orders_tenant_number ON work_orders (tenant_id, number);
CREATE UNIQUE INDEX uq_work_orders_quotation
  ON work_orders (tenant_id, quotation_id)
  WHERE quotation_id IS NOT NULL;
CREATE INDEX idx_work_orders_tenant_status ON work_orders (tenant_id, status);
CREATE INDEX idx_work_orders_customer ON work_orders (tenant_id, customer_id);
CREATE INDEX idx_work_orders_request ON work_orders (tenant_id, request_id);

CREATE TABLE work_order_items (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id        uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  work_order_id    uuid        NOT NULL REFERENCES work_orders(id) ON DELETE CASCADE,
  quotation_item_id uuid       REFERENCES quotation_items(id),
  kind             text        NOT NULL,
  description      text        NOT NULL CHECK (char_length(description) BETWEEN 3 AND 300),
  quantity         numeric(12,3) NOT NULL CHECK (quantity > 0),
  unit_price_cents integer     NOT NULL DEFAULT 0 CHECK (unit_price_cents >= 0),
  total_cents      integer     NOT NULL DEFAULT 0 CHECK (total_cents >= 0),
  created_at       timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_work_order_items_work_order ON work_order_items (work_order_id);

CREATE TABLE work_order_events (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  work_order_id uuid        NOT NULL REFERENCES work_orders(id) ON DELETE CASCADE,
  event_type    text        NOT NULL CHECK (event_type IN (
                            'created','converted_from_quotation','started',
                            'paused','resumed','completed','cancelled','note'
                          )),
  notes         text        CHECK (notes IS NULL OR char_length(notes) <= 2000),
  created_at    timestamptz NOT NULL DEFAULT now(),
  created_by    uuid        REFERENCES auth.users(id)
);

CREATE INDEX idx_work_order_events_work_order ON work_order_events (work_order_id, created_at DESC);

CREATE TABLE work_order_evidence (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  work_order_id uuid        NOT NULL REFERENCES work_orders(id) ON DELETE CASCADE,
  kind          text        NOT NULL CHECK (kind IN ('photo','video','document','signature')),
  storage_path  text        NOT NULL,
  mime_type     text        NOT NULL,
  size_bytes    bigint      NOT NULL CHECK (size_bytes > 0 AND size_bytes <= 52428800),
  checksum      text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  created_by    uuid        REFERENCES auth.users(id)
);

CREATE INDEX idx_work_order_evidence_work_order ON work_order_evidence (work_order_id);

CREATE TRIGGER trg_work_orders_updated_at
  BEFORE UPDATE ON work_orders
  FOR EACH ROW EXECUTE FUNCTION _sf_update_updated_at();

CREATE OR REPLACE FUNCTION _sf_set_work_order_meta()
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

  IF NEW.request_id IS NOT NULL THEN
    SELECT tenant_id INTO v_tenant_id FROM service_requests WHERE id = NEW.request_id;
    IF v_tenant_id IS NULL OR v_tenant_id <> NEW.tenant_id THEN
      RAISE EXCEPTION 'Chamado fora do tenant autorizado.'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  IF NEW.quotation_id IS NOT NULL THEN
    SELECT tenant_id INTO v_tenant_id FROM quotations WHERE id = NEW.quotation_id;
    IF v_tenant_id IS NULL OR v_tenant_id <> NEW.tenant_id THEN
      RAISE EXCEPTION 'Orcamento fora do tenant autorizado.'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.number := COALESCE(NULLIF(NEW.number, 0), next_sequence(NEW.tenant_id, 'work_order'));
    NEW.created_by := auth.uid();
    NEW.updated_by := auth.uid();
  ELSE
    NEW.tenant_id := OLD.tenant_id;
    NEW.number := OLD.number;
    NEW.updated_by := auth.uid();
    IF NEW.status = 'done' AND OLD.status <> 'done' THEN
      NEW.completed_at := COALESCE(NEW.completed_at, now());
    END IF;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_work_orders_meta
  BEFORE INSERT OR UPDATE ON work_orders
  FOR EACH ROW EXECUTE FUNCTION _sf_set_work_order_meta();

CREATE OR REPLACE FUNCTION _work_order_json(p_work_order_id uuid)
RETURNS jsonb LANGUAGE sql SECURITY DEFINER
SET search_path = public
AS $$
  SELECT to_jsonb(wo)
    || jsonb_build_object(
      'customers', jsonb_build_object('name', c.name),
      'service_requests', CASE
        WHEN sr.id IS NULL THEN NULL ELSE jsonb_build_object('title', sr.title)
      END,
      'quotations', CASE
        WHEN q.id IS NULL THEN NULL ELSE jsonb_build_object('number', q.number)
      END
    )
  FROM work_orders wo
  JOIN customers c ON c.id = wo.customer_id
  LEFT JOIN service_requests sr ON sr.id = wo.request_id
  LEFT JOIN quotations q ON q.id = wo.quotation_id
  WHERE wo.id = p_work_order_id;
$$;

CREATE OR REPLACE FUNCTION convert_approved_quotation_to_work_order(
  p_quotation_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_quote quotations;
  v_work_order_id uuid;
  v_item quotation_items;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL OR NOT has_permission('work_orders.write') THEN
    RAISE EXCEPTION 'Permissao insuficiente para criar OS.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_quote
  FROM quotations
  WHERE id = p_quotation_id AND tenant_id = v_tenant_id;

  IF v_quote.id IS NULL THEN
    RAISE EXCEPTION 'Orcamento nao encontrado.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_quote.status <> 'approved' THEN
    RAISE EXCEPTION 'Apenas orcamento aprovado pode virar OS.'
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT id INTO v_work_order_id
  FROM work_orders
  WHERE tenant_id = v_tenant_id AND quotation_id = p_quotation_id;

  IF v_work_order_id IS NULL THEN
    INSERT INTO work_orders (
      tenant_id, number, customer_id, request_id, quotation_id,
      status, title, description, total_cents
    ) VALUES (
      v_tenant_id, next_sequence(v_tenant_id, 'work_order'), v_quote.customer_id,
      v_quote.request_id, v_quote.id, 'opened',
      'OS do orçamento #' || lpad(v_quote.number::text, 5, '0'),
      COALESCE(v_quote.notes, 'Execução gerada a partir de orçamento aprovado.'),
      v_quote.total_cents
    )
    RETURNING id INTO v_work_order_id;

    FOR v_item IN
      SELECT *
      FROM quotation_items
      WHERE quotation_id = v_quote.id
        AND version_id = v_quote.current_version_id
      ORDER BY created_at
    LOOP
      INSERT INTO work_order_items (
        tenant_id, work_order_id, quotation_item_id, kind,
        description, quantity, unit_price_cents, total_cents
      ) VALUES (
        v_tenant_id, v_work_order_id, v_item.id, v_item.kind,
        v_item.description, v_item.quantity, v_item.unit_price_cents,
        v_item.total_cents
      );
    END LOOP;

    INSERT INTO work_order_events (
      tenant_id, work_order_id, event_type, notes, created_by
    ) VALUES (
      v_tenant_id, v_work_order_id, 'converted_from_quotation',
      'OS criada a partir de orçamento aprovado.', auth.uid()
    );

    IF v_quote.request_id IS NOT NULL THEN
      UPDATE service_requests
      SET status = 'converted_to_work_order'
      WHERE id = v_quote.request_id
        AND tenant_id = v_tenant_id
        AND status NOT IN ('cancelled','closed');
    END IF;

    PERFORM log_audit(
      v_tenant_id,
      'work_order.created_from_quotation',
      'work_orders',
      v_work_order_id::text,
      NULL,
      jsonb_build_object('quotation_id', p_quotation_id)
    );
  END IF;

  RETURN _work_order_json(v_work_order_id);
END;
$$;

CREATE OR REPLACE FUNCTION transition_work_order(
  p_work_order_id uuid,
  p_to_status text,
  p_notes text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_current work_orders;
  v_event text;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL OR NOT (has_permission('work_orders.execute') OR has_permission('work_orders.manage')) THEN
    RAISE EXCEPTION 'Permissao insuficiente para executar OS.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_current
  FROM work_orders
  WHERE id = p_work_order_id AND tenant_id = v_tenant_id;

  IF v_current.id IS NULL THEN
    RAISE EXCEPTION 'OS nao encontrada.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_to_status NOT IN ('opened','scheduled','in_progress','awaiting_customer','paused','done','cancelled') THEN
    RAISE EXCEPTION 'Status de OS invalido.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_current.status IN ('done','cancelled') THEN
    RAISE EXCEPTION 'OS finalizada nao pode mudar de status.'
      USING ERRCODE = 'check_violation';
  END IF;

  UPDATE work_orders
  SET status = p_to_status,
      completed_at = CASE WHEN p_to_status = 'done' THEN now() ELSE completed_at END
  WHERE id = p_work_order_id;

  v_event := CASE p_to_status
    WHEN 'in_progress' THEN 'started'
    WHEN 'paused' THEN 'paused'
    WHEN 'done' THEN 'completed'
    WHEN 'cancelled' THEN 'cancelled'
    ELSE 'note'
  END;

  INSERT INTO work_order_events (
    tenant_id, work_order_id, event_type, notes, created_by
  ) VALUES (
    v_tenant_id, p_work_order_id, v_event, p_notes, auth.uid()
  );

  PERFORM log_audit(
    v_tenant_id,
    'work_order.status_changed',
    'work_orders',
    p_work_order_id::text,
    jsonb_build_object('status', v_current.status),
    jsonb_build_object('status', p_to_status)
  );

  RETURN _work_order_json(p_work_order_id);
END;
$$;

ALTER TABLE work_orders ENABLE ROW LEVEL SECURITY;
ALTER TABLE work_order_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE work_order_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE work_order_evidence ENABLE ROW LEVEL SECURITY;

CREATE POLICY "work_orders_select" ON work_orders
  FOR SELECT
  USING (tenant_id = current_tenant_id() AND has_permission('work_orders.read'));

CREATE POLICY "work_orders_insert" ON work_orders
  FOR INSERT
  WITH CHECK (has_permission('work_orders.write'));

CREATE POLICY "work_orders_update" ON work_orders
  FOR UPDATE
  USING (
    tenant_id = current_tenant_id()
    AND (has_permission('work_orders.write') OR has_permission('work_orders.execute') OR has_permission('work_orders.manage'))
  )
  WITH CHECK (
    tenant_id = current_tenant_id()
    AND (has_permission('work_orders.write') OR has_permission('work_orders.execute') OR has_permission('work_orders.manage'))
  );

CREATE POLICY "work_order_items_select" ON work_order_items
  FOR SELECT
  USING (tenant_id = current_tenant_id() AND has_permission('work_orders.read'));

CREATE POLICY "work_order_items_insert" ON work_order_items
  FOR INSERT
  WITH CHECK (has_permission('work_orders.write'));

CREATE POLICY "work_order_events_select" ON work_order_events
  FOR SELECT
  USING (tenant_id = current_tenant_id() AND has_permission('work_orders.read'));

CREATE POLICY "work_order_events_insert" ON work_order_events
  FOR INSERT
  WITH CHECK (has_permission('work_orders.execute') OR has_permission('work_orders.manage'));

CREATE POLICY "work_order_evidence_select" ON work_order_evidence
  FOR SELECT
  USING (tenant_id = current_tenant_id() AND has_permission('work_orders.read'));

CREATE POLICY "work_order_evidence_insert" ON work_order_evidence
  FOR INSERT
  WITH CHECK (has_permission('work_orders.execute'));

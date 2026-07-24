-- =============================================================================
-- Migration: 0005_quotations
-- Descricao: Orcamentos, versoes, itens, links publicos e aprovacoes — Entrega 6
-- Depende de: 0001_foundation, 0002_customers, 0003_service_requests
-- Rollback: supabase/rollbacks/0005_quotations_rollback.sql
-- =============================================================================

CREATE TABLE quotations (
  id                 uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id          uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  number             bigint      NOT NULL,
  customer_id        uuid        NOT NULL REFERENCES customers(id),
  request_id         uuid        REFERENCES service_requests(id),
  current_version_id uuid,
  status             text        NOT NULL DEFAULT 'draft'
                                  CHECK (status IN (
                                    'draft','under_review','sent','viewed',
                                    'awaiting_approval','approved','rejected',
                                    'change_requested','expired','cancelled'
                                  )),
  valid_until        date,
  subtotal_cents     integer     NOT NULL DEFAULT 0 CHECK (subtotal_cents >= 0),
  discount_cents     integer     NOT NULL DEFAULT 0 CHECK (discount_cents >= 0),
  tax_cents          integer     NOT NULL DEFAULT 0 CHECK (tax_cents >= 0),
  total_cents        integer     NOT NULL DEFAULT 0 CHECK (total_cents >= 0),
  notes              text        CHECK (notes IS NULL OR char_length(notes) <= 2000),
  terms              text        CHECK (terms IS NULL OR char_length(terms) <= 4000),
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  created_by         uuid        REFERENCES auth.users(id),
  updated_by         uuid        REFERENCES auth.users(id)
);

CREATE UNIQUE INDEX uq_quotations_tenant_number ON quotations (tenant_id, number);
CREATE INDEX idx_quotations_tenant_status ON quotations (tenant_id, status);
CREATE INDEX idx_quotations_customer ON quotations (tenant_id, customer_id);
CREATE INDEX idx_quotations_request ON quotations (tenant_id, request_id);

CREATE TABLE quotation_versions (
  id                   uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id            uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  quotation_id         uuid        NOT NULL REFERENCES quotations(id) ON DELETE CASCADE,
  version_number       integer     NOT NULL CHECK (version_number > 0),
  subtotal_cents       integer     NOT NULL DEFAULT 0 CHECK (subtotal_cents >= 0),
  discount_cents       integer     NOT NULL DEFAULT 0 CHECK (discount_cents >= 0),
  tax_cents            integer     NOT NULL DEFAULT 0 CHECK (tax_cents >= 0),
  total_cents          integer     NOT NULL DEFAULT 0 CHECK (total_cents >= 0),
  internal_cost_cents  integer     NOT NULL DEFAULT 0 CHECK (internal_cost_cents >= 0),
  gross_margin_cents   integer     NOT NULL DEFAULT 0,
  snapshot             jsonb       NOT NULL DEFAULT '{}'::jsonb,
  created_at           timestamptz NOT NULL DEFAULT now(),
  created_by           uuid        REFERENCES auth.users(id),
  CONSTRAINT uq_quotation_versions_number UNIQUE (quotation_id, version_number)
);

ALTER TABLE quotations
  ADD CONSTRAINT fk_quotations_current_version
  FOREIGN KEY (current_version_id) REFERENCES quotation_versions(id);

CREATE INDEX idx_quotation_versions_quote ON quotation_versions (quotation_id, version_number DESC);

CREATE TABLE quotation_items (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id        uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  quotation_id     uuid        NOT NULL REFERENCES quotations(id) ON DELETE CASCADE,
  version_id       uuid        NOT NULL REFERENCES quotation_versions(id) ON DELETE CASCADE,
  kind             text        NOT NULL CHECK (kind IN (
                              'service','labor_hour','material','equipment',
                              'travel','tax','discount','other'
                            )),
  description      text        NOT NULL CHECK (char_length(description) BETWEEN 3 AND 300),
  quantity         numeric(12,3) NOT NULL CHECK (quantity > 0),
  unit_price_cents integer     NOT NULL CHECK (unit_price_cents >= 0),
  unit_cost_cents  integer     NOT NULL DEFAULT 0 CHECK (unit_cost_cents >= 0),
  total_cents      integer     NOT NULL CHECK (total_cents >= 0),
  created_at       timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_quotation_items_version ON quotation_items (version_id);
CREATE INDEX idx_quotation_items_quote ON quotation_items (quotation_id);

CREATE TABLE quotation_public_links (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  quotation_id uuid       NOT NULL REFERENCES quotations(id) ON DELETE CASCADE,
  version_id  uuid        NOT NULL REFERENCES quotation_versions(id) ON DELETE CASCADE,
  token_hash  text        NOT NULL UNIQUE,
  expires_at  timestamptz NOT NULL,
  revoked_at  timestamptz,
  use_count   integer     NOT NULL DEFAULT 0 CHECK (use_count >= 0),
  last_access_at timestamptz,
  created_at  timestamptz NOT NULL DEFAULT now(),
  created_by  uuid        REFERENCES auth.users(id)
);

CREATE INDEX idx_quotation_public_links_quote ON quotation_public_links (quotation_id);

CREATE TABLE quotation_approvals (
  id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  quotation_id   uuid        NOT NULL REFERENCES quotations(id) ON DELETE CASCADE,
  version_id     uuid        NOT NULL REFERENCES quotation_versions(id) ON DELETE CASCADE,
  decision       text        NOT NULL CHECK (decision IN ('approved','rejected','change_requested')),
  approver_name  text        NOT NULL CHECK (char_length(approver_name) BETWEEN 2 AND 160),
  comments       text        CHECK (comments IS NULL OR char_length(comments) <= 1000),
  decided_at     timestamptz NOT NULL DEFAULT now(),
  ip_hash        text,
  user_agent     text
);

CREATE UNIQUE INDEX uq_quotation_approved_once
  ON quotation_approvals (quotation_id)
  WHERE decision = 'approved';

CREATE TRIGGER trg_quotations_updated_at
  BEFORE UPDATE ON quotations
  FOR EACH ROW EXECUTE FUNCTION _sf_update_updated_at();

CREATE OR REPLACE FUNCTION _sf_set_quotation_meta()
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

  IF TG_OP = 'INSERT' THEN
    NEW.number := COALESCE(NULLIF(NEW.number, 0), next_sequence(NEW.tenant_id, 'quote'));
    NEW.created_by := auth.uid();
    NEW.updated_by := auth.uid();
  ELSE
    NEW.tenant_id := OLD.tenant_id;
    NEW.number := OLD.number;
    NEW.updated_by := auth.uid();
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_quotations_meta
  BEFORE INSERT OR UPDATE ON quotations
  FOR EACH ROW EXECUTE FUNCTION _sf_set_quotation_meta();

CREATE OR REPLACE FUNCTION create_quotation(
  p_customer_id uuid,
  p_request_id uuid,
  p_valid_until date,
  p_notes text,
  p_terms text,
  p_items jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_quote quotations;
  v_version_id uuid;
  v_item jsonb;
  v_kind text;
  v_quantity numeric;
  v_unit_price integer;
  v_unit_cost integer;
  v_total integer;
  v_subtotal integer := 0;
  v_discount integer := 0;
  v_tax integer := 0;
  v_cost integer := 0;
  v_customer_name text;
  v_request_title text;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'Nenhuma membership ativa encontrada.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF NOT has_permission('quotations.write') THEN
    RAISE EXCEPTION 'Permissao insuficiente para criar orcamento.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Inclua ao menos um item.'
      USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO quotations (
    tenant_id, number, customer_id, request_id, valid_until, notes, terms
  ) VALUES (
    v_tenant_id, next_sequence(v_tenant_id, 'quote'), p_customer_id,
    p_request_id, p_valid_until, p_notes, p_terms
  )
  RETURNING * INTO v_quote;

  INSERT INTO quotation_versions (tenant_id, quotation_id, version_number)
  VALUES (v_tenant_id, v_quote.id, 1)
  RETURNING id INTO v_version_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_kind := v_item->>'kind';
    v_quantity := COALESCE((v_item->>'quantity')::numeric, 0);
    v_unit_price := COALESCE((v_item->>'unit_price_cents')::integer, 0);
    v_unit_cost := COALESCE((v_item->>'unit_cost_cents')::integer, 0);
    v_total := ROUND(v_quantity * v_unit_price);

    IF v_quantity <= 0 OR v_unit_price < 0 OR v_unit_cost < 0 THEN
      RAISE EXCEPTION 'Item de orcamento invalido.'
        USING ERRCODE = 'check_violation';
    END IF;

    IF v_kind = 'discount' THEN
      v_discount := v_discount + v_total;
    ELSIF v_kind = 'tax' THEN
      v_tax := v_tax + v_total;
    ELSE
      v_subtotal := v_subtotal + v_total;
    END IF;
    v_cost := v_cost + ROUND(v_quantity * v_unit_cost);

    INSERT INTO quotation_items (
      tenant_id, quotation_id, version_id, kind, description,
      quantity, unit_price_cents, unit_cost_cents, total_cents
    ) VALUES (
      v_tenant_id, v_quote.id, v_version_id, v_kind,
      LEFT(TRIM(v_item->>'description'), 300),
      v_quantity, v_unit_price, v_unit_cost, v_total
    );
  END LOOP;

  UPDATE quotation_versions
  SET subtotal_cents = v_subtotal,
      discount_cents = v_discount,
      tax_cents = v_tax,
      total_cents = GREATEST(v_subtotal + v_tax - v_discount, 0),
      internal_cost_cents = v_cost,
      gross_margin_cents = GREATEST(v_subtotal + v_tax - v_discount, 0) - v_cost,
      snapshot = jsonb_build_object('items', p_items)
  WHERE id = v_version_id;

  UPDATE quotations
  SET current_version_id = v_version_id,
      subtotal_cents = v_subtotal,
      discount_cents = v_discount,
      tax_cents = v_tax,
      total_cents = GREATEST(v_subtotal + v_tax - v_discount, 0)
  WHERE id = v_quote.id
  RETURNING * INTO v_quote;

  SELECT name INTO v_customer_name FROM customers WHERE id = v_quote.customer_id;
  SELECT title INTO v_request_title FROM service_requests WHERE id = v_quote.request_id;

  PERFORM log_audit(
    v_tenant_id,
    'quotation.created',
    'quotations',
    v_quote.id::text,
    NULL,
    jsonb_build_object('number', v_quote.number, 'total_cents', v_quote.total_cents)
  );

  RETURN to_jsonb(v_quote)
    || jsonb_build_object('customers', jsonb_build_object('name', v_customer_name))
    || jsonb_build_object('service_requests', CASE WHEN v_request_title IS NULL THEN NULL ELSE jsonb_build_object('title', v_request_title) END);
END;
$$;

ALTER TABLE quotations ENABLE ROW LEVEL SECURITY;
ALTER TABLE quotation_versions ENABLE ROW LEVEL SECURITY;
ALTER TABLE quotation_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE quotation_public_links ENABLE ROW LEVEL SECURITY;
ALTER TABLE quotation_approvals ENABLE ROW LEVEL SECURITY;

CREATE POLICY "quotations_select" ON quotations
  FOR SELECT TO authenticated
  USING (tenant_id = current_tenant_id() AND has_permission('quotations.read'));

CREATE POLICY "quotations_insert" ON quotations
  FOR INSERT TO authenticated
  WITH CHECK (has_permission('quotations.write'));

CREATE POLICY "quotations_update" ON quotations
  FOR UPDATE TO authenticated
  USING (tenant_id = current_tenant_id() AND has_permission('quotations.write'))
  WITH CHECK (tenant_id = current_tenant_id() AND has_permission('quotations.write'));

CREATE POLICY "quotation_versions_select" ON quotation_versions
  FOR SELECT TO authenticated
  USING (tenant_id = current_tenant_id() AND has_permission('quotations.read'));

CREATE POLICY "quotation_items_select" ON quotation_items
  FOR SELECT TO authenticated
  USING (tenant_id = current_tenant_id() AND has_permission('quotations.read'));

CREATE POLICY "quotation_public_links_select" ON quotation_public_links
  FOR SELECT TO authenticated
  USING (tenant_id = current_tenant_id() AND has_permission('quotations.read'));

CREATE POLICY "quotation_approvals_select" ON quotation_approvals
  FOR SELECT TO authenticated
  USING (tenant_id = current_tenant_id() AND has_permission('quotations.read'));

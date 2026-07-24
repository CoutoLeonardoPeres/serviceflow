-- =============================================================================
-- Migration: 0014_customer_satisfaction
-- Descricao: Pesquisa de satisfacao simples vinculada a OS — F2
-- Depende de: 0001_foundation, 0008_work_orders
-- Rollback: supabase/rollbacks/0014_customer_satisfaction_rollback.sql
-- =============================================================================

CREATE TABLE work_order_satisfaction (
  id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  work_order_id  uuid        NOT NULL REFERENCES work_orders(id) ON DELETE CASCADE,
  customer_id    uuid        NOT NULL REFERENCES customers(id),
  rating         integer     NOT NULL CHECK (rating BETWEEN 1 AND 5),
  contact_name   text        CHECK (contact_name IS NULL OR char_length(contact_name) <= 160),
  comment        text        CHECK (comment IS NULL OR char_length(comment) <= 1000),
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  created_by     uuid        REFERENCES auth.users(id),
  updated_by     uuid        REFERENCES auth.users(id),
  CONSTRAINT uq_work_order_satisfaction_once UNIQUE (work_order_id)
);

CREATE INDEX idx_work_order_satisfaction_tenant
  ON work_order_satisfaction (tenant_id, created_at DESC);
CREATE INDEX idx_work_order_satisfaction_customer
  ON work_order_satisfaction (tenant_id, customer_id);

CREATE TRIGGER trg_work_order_satisfaction_updated_at
  BEFORE UPDATE ON work_order_satisfaction
  FOR EACH ROW EXECUTE FUNCTION _sf_update_updated_at();

CREATE OR REPLACE FUNCTION _sf_set_work_order_satisfaction_meta()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_work_order work_orders;
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

  SELECT * INTO v_work_order
  FROM work_orders
  WHERE id = NEW.work_order_id;

  IF v_work_order.id IS NULL OR v_work_order.tenant_id <> NEW.tenant_id THEN
    RAISE EXCEPTION 'OS fora do tenant autorizado.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  NEW.customer_id := v_work_order.customer_id;

  IF TG_OP = 'INSERT' THEN
    NEW.created_by := auth.uid();
    NEW.updated_by := auth.uid();
  ELSE
    NEW.tenant_id := OLD.tenant_id;
    NEW.work_order_id := OLD.work_order_id;
    NEW.customer_id := OLD.customer_id;
    NEW.created_by := OLD.created_by;
    NEW.updated_by := auth.uid();
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_work_order_satisfaction_meta
  BEFORE INSERT OR UPDATE ON work_order_satisfaction
  FOR EACH ROW EXECUTE FUNCTION _sf_set_work_order_satisfaction_meta();

CREATE OR REPLACE FUNCTION record_work_order_satisfaction(
  p_work_order_id uuid,
  p_rating integer,
  p_contact_name text DEFAULT NULL,
  p_comment text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_work_order work_orders;
  v_satisfaction_id uuid;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL OR NOT (has_permission('work_orders.execute') OR has_permission('work_orders.manage')) THEN
    RAISE EXCEPTION 'Permissao insuficiente para registrar satisfacao.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_work_order
  FROM work_orders
  WHERE id = p_work_order_id AND tenant_id = v_tenant_id;

  IF v_work_order.id IS NULL THEN
    RAISE EXCEPTION 'OS nao encontrada.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_work_order.status <> 'done' THEN
    RAISE EXCEPTION 'Satisfacao so pode ser registrada apos concluir a OS.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF p_rating < 1 OR p_rating > 5 THEN
    RAISE EXCEPTION 'Nota de satisfacao invalida.'
      USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO work_order_satisfaction (
    tenant_id, work_order_id, customer_id, rating, contact_name, comment
  ) VALUES (
    v_tenant_id,
    p_work_order_id,
    v_work_order.customer_id,
    p_rating,
    NULLIF(LEFT(TRIM(COALESCE(p_contact_name, '')), 160), ''),
    NULLIF(LEFT(TRIM(COALESCE(p_comment, '')), 1000), '')
  )
  ON CONFLICT (work_order_id) DO UPDATE
  SET rating = EXCLUDED.rating,
      contact_name = EXCLUDED.contact_name,
      comment = EXCLUDED.comment,
      updated_at = now(),
      updated_by = auth.uid()
  RETURNING id INTO v_satisfaction_id;

  INSERT INTO work_order_events (
    tenant_id, work_order_id, event_type, notes, created_by
  ) VALUES (
    v_tenant_id,
    p_work_order_id,
    'note',
    'Satisfacao registrada: ' || p_rating::text || '/5',
    auth.uid()
  );

  PERFORM log_audit(
    v_tenant_id,
    'work_order.satisfaction.recorded',
    'work_order_satisfaction',
    v_satisfaction_id::text,
    NULL,
    jsonb_build_object('work_order_id', p_work_order_id, 'rating', p_rating)
  );

  RETURN to_jsonb(s)
  FROM work_order_satisfaction s
  WHERE s.id = v_satisfaction_id;
END;
$$;

ALTER TABLE work_order_satisfaction ENABLE ROW LEVEL SECURITY;

CREATE POLICY "work_order_satisfaction_select" ON work_order_satisfaction
  FOR SELECT
  USING (tenant_id = current_tenant_id() AND has_permission('work_orders.read'));

CREATE POLICY "work_order_satisfaction_insert" ON work_order_satisfaction
  FOR INSERT
  WITH CHECK (has_permission('work_orders.execute') OR has_permission('work_orders.manage'));

CREATE POLICY "work_order_satisfaction_update" ON work_order_satisfaction
  FOR UPDATE
  USING (
    tenant_id = current_tenant_id()
    AND (has_permission('work_orders.execute') OR has_permission('work_orders.manage'))
  )
  WITH CHECK (
    tenant_id = current_tenant_id()
    AND (has_permission('work_orders.execute') OR has_permission('work_orders.manage'))
  );

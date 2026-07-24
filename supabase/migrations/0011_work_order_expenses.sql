-- =============================================================================
-- Migration: 0011_work_order_expenses
-- Descricao: Despesas operacionais da ordem de servico — Entrega 7
-- Depende de: 0008_work_orders
-- Rollback: supabase/rollbacks/0011_work_order_expenses_rollback.sql
-- =============================================================================

CREATE TABLE work_order_expenses (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  work_order_id uuid        NOT NULL REFERENCES work_orders(id) ON DELETE CASCADE,
  kind          text        NOT NULL CHECK (kind IN (
                              'travel','toll','parking','meal',
                              'lodging','freight','other'
                            )),
  description   text        CHECK (description IS NULL OR char_length(description) <= 300),
  amount_cents  integer     NOT NULL CHECK (amount_cents > 0),
  receipt_path  text,
  created_at    timestamptz NOT NULL DEFAULT now(),
  created_by    uuid        REFERENCES auth.users(id)
);

CREATE INDEX idx_work_order_expenses_work_order
  ON work_order_expenses (work_order_id, created_at DESC);

CREATE OR REPLACE FUNCTION add_work_order_expense(
  p_work_order_id uuid,
  p_kind text,
  p_amount_cents integer,
  p_description text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_work_order work_orders;
  v_expense_id uuid;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL OR NOT has_permission('work_orders.execute') THEN
    RAISE EXCEPTION 'Permissao insuficiente para registrar despesa.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_work_order
  FROM work_orders
  WHERE id = p_work_order_id AND tenant_id = v_tenant_id;

  IF v_work_order.id IS NULL THEN
    RAISE EXCEPTION 'OS nao encontrada.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_work_order.status IN ('done','cancelled') THEN
    RAISE EXCEPTION 'OS finalizada nao aceita despesa.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF p_kind NOT IN ('travel','toll','parking','meal','lodging','freight','other')
     OR p_amount_cents <= 0 THEN
    RAISE EXCEPTION 'Despesa invalida.'
      USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO work_order_expenses (
    tenant_id, work_order_id, kind, description, amount_cents, created_by
  ) VALUES (
    v_tenant_id, p_work_order_id, p_kind,
    NULLIF(LEFT(TRIM(COALESCE(p_description, '')), 300), ''),
    p_amount_cents, auth.uid()
  )
  RETURNING id INTO v_expense_id;

  INSERT INTO work_order_events (
    tenant_id, work_order_id, event_type, notes, created_by
  ) VALUES (
    v_tenant_id, p_work_order_id, 'note',
    'Despesa registrada: ' || p_kind || ' / ' || p_amount_cents::text || ' centavos',
    auth.uid()
  );

  PERFORM log_audit(
    v_tenant_id,
    'work_order.expense.created',
    'work_order_expenses',
    v_expense_id::text,
    NULL,
    jsonb_build_object(
      'work_order_id', p_work_order_id,
      'kind', p_kind,
      'amount_cents', p_amount_cents
    )
  );

  RETURN jsonb_build_object('id', v_expense_id);
END;
$$;

ALTER TABLE work_order_expenses ENABLE ROW LEVEL SECURITY;

CREATE POLICY "work_order_expenses_select" ON work_order_expenses
  FOR SELECT
  USING (tenant_id = current_tenant_id() AND has_permission('work_orders.read'));

CREATE POLICY "work_order_expenses_insert" ON work_order_expenses
  FOR INSERT
  WITH CHECK (has_permission('work_orders.execute'));

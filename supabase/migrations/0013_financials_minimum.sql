-- =============================================================================
-- Migration: 0013_financials_minimum
-- Descricao: Recebiveis, pagamentos manuais e recibos numerados — Entrega 8
-- Depende de: 0001_foundation, 0002_customers, 0008_work_orders
-- Rollback: supabase/rollbacks/0013_financials_minimum_rollback.sql
-- =============================================================================

CREATE TABLE receivables (
  id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  work_order_id  uuid        REFERENCES work_orders(id),
  customer_id    uuid        NOT NULL REFERENCES customers(id),
  description    text        NOT NULL CHECK (char_length(description) BETWEEN 3 AND 240),
  due_date       date        NOT NULL,
  amount_cents   integer     NOT NULL CHECK (amount_cents > 0),
  balance_cents  integer     NOT NULL CHECK (balance_cents >= 0),
  status         text        NOT NULL DEFAULT 'open'
                             CHECK (status IN ('open','partially_paid','paid','cancelled')),
  created_at     timestamptz NOT NULL DEFAULT now(),
  updated_at     timestamptz NOT NULL DEFAULT now(),
  created_by     uuid        REFERENCES auth.users(id),
  updated_by     uuid        REFERENCES auth.users(id),
  CONSTRAINT chk_receivables_balance CHECK (balance_cents <= amount_cents)
);

CREATE UNIQUE INDEX uq_receivables_work_order
  ON receivables (tenant_id, work_order_id)
  WHERE work_order_id IS NOT NULL;
CREATE INDEX idx_receivables_tenant_status ON receivables (tenant_id, status, due_date);
CREATE INDEX idx_receivables_customer ON receivables (tenant_id, customer_id);

CREATE TABLE payment_records (
  id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  receivable_id  uuid        NOT NULL REFERENCES receivables(id) ON DELETE CASCADE,
  method         text        NOT NULL CHECK (method IN (
                               'cash','pix_manual','transfer','card_machine','other'
                             )),
  amount_cents   integer     NOT NULL CHECK (amount_cents > 0),
  fees_cents     integer     NOT NULL DEFAULT 0 CHECK (fees_cents >= 0),
  net_cents      integer     NOT NULL CHECK (net_cents > 0),
  paid_at        timestamptz NOT NULL DEFAULT now(),
  reference      text        CHECK (reference IS NULL OR char_length(reference) <= 120),
  notes          text        CHECK (notes IS NULL OR char_length(notes) <= 500),
  created_at     timestamptz NOT NULL DEFAULT now(),
  received_by    uuid        REFERENCES auth.users(id)
);

CREATE INDEX idx_payment_records_receivable ON payment_records (receivable_id, paid_at DESC);

CREATE TABLE receipts (
  id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  number         bigint      NOT NULL,
  receivable_id  uuid        NOT NULL REFERENCES receivables(id),
  payment_id     uuid        NOT NULL REFERENCES payment_records(id),
  work_order_id  uuid        REFERENCES work_orders(id),
  customer_id    uuid        NOT NULL REFERENCES customers(id),
  amount_cents   integer     NOT NULL CHECK (amount_cents > 0),
  pdf_path       text,
  checksum       text,
  issued_at      timestamptz NOT NULL DEFAULT now(),
  issued_by      uuid        REFERENCES auth.users(id)
);

CREATE UNIQUE INDEX uq_receipts_tenant_number ON receipts (tenant_id, number);
CREATE INDEX idx_receipts_receivable ON receipts (receivable_id, issued_at DESC);

CREATE TRIGGER trg_receivables_updated_at
  BEFORE UPDATE ON receivables
  FOR EACH ROW EXECUTE FUNCTION _sf_update_updated_at();

CREATE OR REPLACE FUNCTION _sf_set_receivable_meta()
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
    RAISE EXCEPTION 'Cliente fora do tenant autorizado.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF NEW.work_order_id IS NOT NULL THEN
    SELECT tenant_id INTO v_tenant_id FROM work_orders WHERE id = NEW.work_order_id;
    IF v_tenant_id IS NULL OR v_tenant_id <> NEW.tenant_id THEN
      RAISE EXCEPTION 'OS fora do tenant autorizado.'
        USING ERRCODE = 'insufficient_privilege';
    END IF;
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.balance_cents := COALESCE(NULLIF(NEW.balance_cents, 0), NEW.amount_cents);
    NEW.created_by := auth.uid();
    NEW.updated_by := auth.uid();
  ELSE
    NEW.tenant_id := OLD.tenant_id;
    NEW.created_by := OLD.created_by;
    NEW.updated_by := auth.uid();
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_receivables_meta
  BEFORE INSERT OR UPDATE ON receivables
  FOR EACH ROW EXECUTE FUNCTION _sf_set_receivable_meta();

CREATE OR REPLACE FUNCTION create_receivable_from_work_order(
  p_work_order_id uuid,
  p_due_date date DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_work_order work_orders;
  v_receivable_id uuid;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL OR NOT has_permission('financials.write') THEN
    RAISE EXCEPTION 'Permissao insuficiente para criar recebivel.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_work_order
  FROM work_orders
  WHERE id = p_work_order_id AND tenant_id = v_tenant_id;

  IF v_work_order.id IS NULL THEN
    RAISE EXCEPTION 'OS nao encontrada.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_work_order.total_cents <= 0 THEN
    RAISE EXCEPTION 'OS sem valor financeiro.'
      USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO receivables (
    tenant_id, work_order_id, customer_id, description, due_date,
    amount_cents, balance_cents, status
  ) VALUES (
    v_tenant_id,
    v_work_order.id,
    v_work_order.customer_id,
    'OS #' || lpad(v_work_order.number::text, 5, '0') || ' - ' || v_work_order.title,
    COALESCE(p_due_date, CURRENT_DATE),
    v_work_order.total_cents,
    v_work_order.total_cents,
    'open'
  )
  ON CONFLICT (tenant_id, work_order_id) WHERE work_order_id IS NOT NULL
  DO UPDATE SET updated_at = now()
  RETURNING id INTO v_receivable_id;

  PERFORM log_audit(
    v_tenant_id,
    'financial.receivable.created_from_work_order',
    'receivables',
    v_receivable_id::text,
    NULL,
    jsonb_build_object('work_order_id', p_work_order_id)
  );

  RETURN to_jsonb(r)
  FROM receivables r
  WHERE r.id = v_receivable_id;
END;
$$;

CREATE OR REPLACE FUNCTION register_manual_payment(
  p_receivable_id uuid,
  p_method text,
  p_amount_cents integer,
  p_reference text DEFAULT NULL,
  p_notes text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_receivable receivables;
  v_payment_id uuid;
  v_receipt_id uuid;
  v_new_balance integer;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL OR NOT has_permission('financials.write') THEN
    RAISE EXCEPTION 'Permissao insuficiente para registrar pagamento.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_receivable
  FROM receivables
  WHERE id = p_receivable_id AND tenant_id = v_tenant_id
  FOR UPDATE;

  IF v_receivable.id IS NULL THEN
    RAISE EXCEPTION 'Recebivel nao encontrado.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_receivable.status = 'cancelled' THEN
    RAISE EXCEPTION 'Recebivel cancelado nao aceita pagamento.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF p_method NOT IN ('cash','pix_manual','transfer','card_machine','other') THEN
    RAISE EXCEPTION 'Forma de pagamento invalida.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF p_amount_cents <= 0 OR p_amount_cents > v_receivable.balance_cents THEN
    RAISE EXCEPTION 'Valor de pagamento invalido.'
      USING ERRCODE = 'check_violation';
  END IF;

  v_new_balance := v_receivable.balance_cents - p_amount_cents;

  INSERT INTO payment_records (
    tenant_id, receivable_id, method, amount_cents, fees_cents, net_cents,
    reference, notes, received_by
  ) VALUES (
    v_tenant_id, p_receivable_id, p_method, p_amount_cents, 0, p_amount_cents,
    p_reference, p_notes, auth.uid()
  )
  RETURNING id INTO v_payment_id;

  UPDATE receivables
  SET balance_cents = v_new_balance,
      status = CASE WHEN v_new_balance = 0 THEN 'paid' ELSE 'partially_paid' END
  WHERE id = p_receivable_id;

  INSERT INTO receipts (
    tenant_id, number, receivable_id, payment_id, work_order_id, customer_id,
    amount_cents, issued_by
  ) VALUES (
    v_tenant_id,
    next_sequence(v_tenant_id, 'receipt'),
    p_receivable_id,
    v_payment_id,
    v_receivable.work_order_id,
    v_receivable.customer_id,
    p_amount_cents,
    auth.uid()
  )
  RETURNING id INTO v_receipt_id;

  PERFORM log_audit(
    v_tenant_id,
    'financial.payment.registered',
    'payment_records',
    v_payment_id::text,
    jsonb_build_object('balance_cents', v_receivable.balance_cents),
    jsonb_build_object('balance_cents', v_new_balance, 'receipt_id', v_receipt_id)
  );

  RETURN jsonb_build_object(
    'payment_id', v_payment_id,
    'receipt_id', v_receipt_id,
    'balance_cents', v_new_balance
  );
END;
$$;

ALTER TABLE receivables ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE receipts ENABLE ROW LEVEL SECURITY;

CREATE POLICY "receivables_select" ON receivables
  FOR SELECT
  USING (tenant_id = current_tenant_id() AND has_permission('financials.read'));

CREATE POLICY "receivables_insert" ON receivables
  FOR INSERT
  WITH CHECK (has_permission('financials.write'));

CREATE POLICY "receivables_update" ON receivables
  FOR UPDATE
  USING (tenant_id = current_tenant_id() AND has_permission('financials.write'))
  WITH CHECK (tenant_id = current_tenant_id() AND has_permission('financials.write'));

CREATE POLICY "payment_records_select" ON payment_records
  FOR SELECT
  USING (tenant_id = current_tenant_id() AND has_permission('financials.read'));

CREATE POLICY "payment_records_insert" ON payment_records
  FOR INSERT
  WITH CHECK (has_permission('financials.write'));

CREATE POLICY "receipts_select" ON receipts
  FOR SELECT
  USING (tenant_id = current_tenant_id() AND has_permission('financials.read'));

CREATE POLICY "receipts_insert" ON receipts
  FOR INSERT
  WITH CHECK (has_permission('financials.write'));

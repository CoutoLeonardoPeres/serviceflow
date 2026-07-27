-- =============================================================================
-- Migration: 0048_payables
-- Descricao: Contas a pagar, geradas automaticamente no recebimento do pedido
--            de compra — F4-P1 (ADR-025)
-- Depende de: 0001_foundation, 0013_financials_minimum, 0044_suppliers_purchase_orders
-- Rollback: supabase/rollbacks/0048_payables_rollback.sql
--
-- ORIGEM: `receive_purchase_order` (0044) ganha um upsert em `payables` na
-- mesma transacao do recebimento — cada recebimento (total ou parcial) soma
-- o valor recebido na conta a pagar do pedido. Fecha a lacuna que a propria
-- 0044 ja deixava documentada: antes, o custo entrava no estoque e o
-- compromisso financeiro ficava fora do sistema.
--
-- MODELO: espelha `receivables`/`payment_records` (0013) de proposito —
-- baixa manual simples, sem `financial_accounts` (conta bancaria/caixa).
-- Reaproveita as permissoes `financials.read`/`financials.write` que ja
-- existem desde 0001 (nao precisa de permissao nova).
--
-- ponytail: due_date = recebimento + 30 dias (prazo padrao fixo). Nao existe
-- campo de prazo de pagamento por fornecedor ainda — adicionar quando houver
-- fornecedor com prazo real diferente de 30 dias.
-- =============================================================================

CREATE TABLE payables (
  id                 uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id          uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  supplier_id        uuid        NOT NULL REFERENCES suppliers(id),
  purchase_order_id  uuid        NOT NULL REFERENCES purchase_orders(id),
  description        text        NOT NULL CHECK (char_length(description) BETWEEN 3 AND 240),
  due_date           date        NOT NULL,
  amount_cents       bigint      NOT NULL CHECK (amount_cents > 0),
  balance_cents      bigint      NOT NULL CHECK (balance_cents >= 0),
  status             text        NOT NULL DEFAULT 'open'
                                 CHECK (status IN ('open','partially_paid','paid','cancelled')),
  created_at         timestamptz NOT NULL DEFAULT now(),
  updated_at         timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT chk_payables_balance CHECK (balance_cents <= amount_cents),
  CONSTRAINT uq_payables_purchase_order UNIQUE (tenant_id, purchase_order_id)
);

CREATE INDEX idx_payables_tenant_status ON payables (tenant_id, status, due_date);
CREATE INDEX idx_payables_supplier ON payables (tenant_id, supplier_id);

CREATE TRIGGER trg_payables_updated_at
  BEFORE UPDATE ON payables
  FOR EACH ROW EXECUTE FUNCTION _sf_update_updated_at();

CREATE TABLE payable_payments (
  id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  payable_id     uuid        NOT NULL REFERENCES payables(id) ON DELETE CASCADE,
  method         text        NOT NULL CHECK (method IN (
                               'cash','pix_manual','transfer','card_machine','other'
                             )),
  amount_cents   integer     NOT NULL CHECK (amount_cents > 0),
  paid_at        timestamptz NOT NULL DEFAULT now(),
  reference      text        CHECK (reference IS NULL OR char_length(reference) <= 120),
  notes          text        CHECK (notes IS NULL OR char_length(notes) <= 500),
  created_at     timestamptz NOT NULL DEFAULT now(),
  paid_by        uuid        REFERENCES auth.users(id)
);

CREATE INDEX idx_payable_payments_payable ON payable_payments (payable_id, paid_at DESC);

-- ── RPC: upsert interno chamado por receive_purchase_order ──────────────────
-- Nao e SECURITY DEFINER proprio: roda dentro do contexto de quem chamou
-- receive_purchase_order (SECURITY DEFINER), igual aos helpers de estoque.

CREATE OR REPLACE FUNCTION _sf_upsert_payable_on_receipt(
  p_tenant_id         uuid,
  p_purchase_order_id uuid,
  p_supplier_id       uuid,
  p_order_number      bigint,
  p_received_value_cents bigint
) RETURNS void LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
  IF p_received_value_cents <= 0 THEN
    RETURN;
  END IF;

  INSERT INTO payables (
    tenant_id, supplier_id, purchase_order_id, description, due_date,
    amount_cents, balance_cents, status
  ) VALUES (
    p_tenant_id,
    p_supplier_id,
    p_purchase_order_id,
    'Pedido de compra #' || lpad(p_order_number::text, 5, '0'),
    CURRENT_DATE + INTERVAL '30 days',
    p_received_value_cents,
    p_received_value_cents,
    'open'
  )
  ON CONFLICT (tenant_id, purchase_order_id) DO UPDATE
  SET amount_cents = payables.amount_cents + EXCLUDED.amount_cents,
      balance_cents = payables.balance_cents + EXCLUDED.amount_cents,
      status = CASE
        WHEN payables.balance_cents + EXCLUDED.amount_cents = 0 THEN 'paid'
        WHEN payables.status = 'paid' THEN 'partially_paid'
        ELSE payables.status
      END;
END;
$$;

-- ── RPC: baixa manual (espelha register_manual_payment) ─────────────────────

CREATE OR REPLACE FUNCTION register_payable_payment(
  p_payable_id uuid,
  p_method text,
  p_amount_cents integer,
  p_reference text DEFAULT NULL,
  p_notes text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_payable payables;
  v_payment_id uuid;
  v_new_balance bigint;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL OR NOT has_permission('financials.write') THEN
    RAISE EXCEPTION 'Permissao insuficiente para registrar pagamento.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_payable
  FROM payables
  WHERE id = p_payable_id AND tenant_id = v_tenant_id
  FOR UPDATE;

  IF v_payable.id IS NULL THEN
    RAISE EXCEPTION 'Conta a pagar nao encontrada.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_payable.status IN ('cancelled', 'paid') THEN
    RAISE EXCEPTION 'Conta a pagar % nao aceita pagamento.', v_payable.status
      USING ERRCODE = 'check_violation';
  END IF;

  IF p_method NOT IN ('cash','pix_manual','transfer','card_machine','other') THEN
    RAISE EXCEPTION 'Forma de pagamento invalida.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF p_amount_cents <= 0 OR p_amount_cents > v_payable.balance_cents THEN
    RAISE EXCEPTION 'Valor de pagamento invalido.'
      USING ERRCODE = 'check_violation';
  END IF;

  v_new_balance := v_payable.balance_cents - p_amount_cents;

  INSERT INTO payable_payments (
    tenant_id, payable_id, method, amount_cents, reference, notes, paid_by
  ) VALUES (
    v_tenant_id, p_payable_id, p_method, p_amount_cents, p_reference, p_notes, auth.uid()
  )
  RETURNING id INTO v_payment_id;

  UPDATE payables
  SET balance_cents = v_new_balance,
      status = CASE WHEN v_new_balance = 0 THEN 'paid' ELSE 'partially_paid' END
  WHERE id = p_payable_id;

  PERFORM log_audit(
    v_tenant_id,
    'financial.payable_payment.registered',
    'payable_payments',
    v_payment_id::text,
    jsonb_build_object('balance_cents', v_payable.balance_cents),
    jsonb_build_object('balance_cents', v_new_balance)
  );

  RETURN jsonb_build_object(
    'payment_id', v_payment_id,
    'balance_cents', v_new_balance
  );
END;
$$;

-- ── RPC: listagem paginada (espelha o padrao de financial_repository) ───────

CREATE OR REPLACE FUNCTION list_payables(
  p_status text DEFAULT NULL
) RETURNS TABLE (
  id uuid,
  supplier_id uuid,
  supplier_name text,
  purchase_order_id uuid,
  purchase_order_number bigint,
  description text,
  due_date date,
  amount_cents bigint,
  balance_cents bigint,
  status text,
  created_at timestamptz
) LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL OR NOT has_permission('financials.read') THEN
    RAISE EXCEPTION 'Permissao financials.read necessaria.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  RETURN QUERY
  SELECT
    p.id, p.supplier_id, s.name, p.purchase_order_id, po.number,
    p.description, p.due_date, p.amount_cents, p.balance_cents, p.status,
    p.created_at
  FROM payables p
  JOIN suppliers s ON s.id = p.supplier_id
  JOIN purchase_orders po ON po.id = p.purchase_order_id
  WHERE p.tenant_id = v_tenant_id
    AND (p_status IS NULL OR p.status = p_status)
  ORDER BY p.due_date, p.created_at DESC;
END;
$$;

-- ── Ligacao com o recebimento (0044) ─────────────────────────────────────────
-- Mesma assinatura de 0044 — CREATE OR REPLACE substitui o corpo, sem
-- armadilha de aridade porque os parametros nao mudam.

CREATE OR REPLACE FUNCTION receive_purchase_order(
  p_order_id uuid,
  p_items    jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id   uuid;
  v_order       purchase_orders;
  v_item        jsonb;
  v_po_item     purchase_order_items;
  v_qty         numeric;
  v_cost        integer;
  v_received    int := 0;
  v_received_value_cents bigint := 0;
  v_all_done    boolean;
  v_new_status  text;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL OR NOT has_permission('purchases.receive') THEN
    RAISE EXCEPTION 'Permissao purchases.receive necessaria.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_order
  FROM purchase_orders
  WHERE id = p_order_id AND tenant_id = v_tenant_id
  FOR UPDATE;

  IF v_order.id IS NULL THEN
    RAISE EXCEPTION 'Pedido nao encontrado.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_order.status NOT IN ('sent','partially_received') THEN
    RAISE EXCEPTION
      'Pedido com status "%" nao aceita recebimento.', v_order.status
      USING ERRCODE = 'check_violation';
  END IF;

  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Informe ao menos um item recebido.'
      USING ERRCODE = 'check_violation';
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    SELECT * INTO v_po_item
    FROM purchase_order_items
    WHERE id = (v_item->>'item_id')::uuid
      AND purchase_order_id = p_order_id
    FOR UPDATE;

    IF v_po_item.id IS NULL THEN
      RAISE EXCEPTION 'Item do pedido nao encontrado.'
        USING ERRCODE = 'insufficient_privilege';
    END IF;

    v_qty := (v_item->>'quantity')::numeric;
    IF v_qty IS NULL OR v_qty <= 0 THEN
      RAISE EXCEPTION 'Quantidade recebida invalida.'
        USING ERRCODE = 'check_violation';
    END IF;

    IF v_po_item.quantity_received + v_qty > v_po_item.quantity_ordered THEN
      RAISE EXCEPTION
        'Recebimento acima do pedido: pedido %, ja recebido %, tentando receber %.',
        v_po_item.quantity_ordered, v_po_item.quantity_received, v_qty
        USING ERRCODE = 'check_violation';
    END IF;

    -- Preco da nota prevalece sobre o cotado, quando informado.
    v_cost := COALESCE(
      (v_item->>'unit_cost_cents')::integer,
      v_po_item.unit_cost_cents
    );
    IF v_cost < 0 THEN
      RAISE EXCEPTION 'Custo recebido invalido.'
        USING ERRCODE = 'check_violation';
    END IF;

    -- E aqui que o estoque entra. Se isto falhar, a transacao inteira volta e
    -- o pedido nao fica marcado como recebido.
    PERFORM record_stock_entry(
      p_product_id       => v_po_item.product_id,
      p_warehouse_id     => v_order.warehouse_id,
      p_quantity         => v_qty,
      p_unit_cost_cents  => v_cost,
      p_reason           => 'Recebimento do pedido #' || v_order.number::text,
      p_related_entity   => 'purchase_orders',
      p_related_entity_id => p_order_id
    );

    UPDATE purchase_order_items
    SET quantity_received = quantity_received + v_qty
    WHERE id = v_po_item.id;

    v_received := v_received + 1;
    v_received_value_cents := v_received_value_cents + round(v_qty * v_cost)::bigint;
  END LOOP;

  SELECT bool_and(quantity_received >= quantity_ordered) INTO v_all_done
  FROM purchase_order_items
  WHERE purchase_order_id = p_order_id;

  v_new_status := CASE WHEN v_all_done THEN 'received' ELSE 'partially_received' END;

  UPDATE purchase_orders
  SET status = v_new_status,
      received_at = CASE WHEN v_all_done THEN now() ELSE received_at END
  WHERE id = p_order_id;

  -- F4-P1 (ADR-025): cada recebimento soma na conta a pagar do pedido.
  PERFORM _sf_upsert_payable_on_receipt(
    v_tenant_id, p_order_id, v_order.supplier_id, v_order.number,
    v_received_value_cents
  );

  PERFORM log_audit(
    v_tenant_id, 'purchase_order.received', 'purchase_orders', p_order_id::text,
    NULL,
    jsonb_build_object(
      'items_received', v_received,
      'status', v_new_status,
      'fully_received', v_all_done,
      'received_value_cents', v_received_value_cents
    )
  );

  RETURN jsonb_build_object(
    'status', v_new_status,
    'fully_received', v_all_done,
    'items_received', v_received
  );
END;
$$;

-- ── RLS ───────────────────────────────────────────────────────────────────

ALTER TABLE payables ENABLE ROW LEVEL SECURITY;
ALTER TABLE payable_payments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "payables_select" ON payables
  FOR SELECT
  USING (tenant_id = current_tenant_id() AND has_permission('financials.read'));

CREATE POLICY "payable_payments_select" ON payable_payments
  FOR SELECT
  USING (tenant_id = current_tenant_id() AND has_permission('financials.read'));

-- Sem policy de INSERT/UPDATE direto: payables nasce só via
-- _sf_upsert_payable_on_receipt (chamado dentro de receive_purchase_order,
-- SECURITY DEFINER) e payable_payments só via register_payable_payment
-- (também SECURITY DEFINER) — igual ao padrão de stock_movements (0042).

COMMENT ON TABLE payables IS
  'Conta a pagar. Criada automaticamente por receive_purchase_order — nao existe insercao manual nesta entrega (F4-P1, ADR-025).';
COMMENT ON COLUMN payables.due_date IS
  'Prazo fixo de 30 dias a partir do recebimento (ponytail): nao ha campo de prazo por fornecedor ainda.';

-- Rollback: 0048_payables
--
-- ATENCAO — ordem de rollback:
--   Rode este script ANTES de 0044_suppliers_purchase_orders_rollback.sql.
--   payables referencia suppliers e purchase_orders; se 0044 cair primeiro,
--   os FKs quebram. Este script tambem RESTAURA a versao de
--   receive_purchase_order de 0044 (sem o upsert de payables) — rodar fora
--   de ordem deixa a funcao chamando _sf_upsert_payable_on_receipt, que
--   este script acabou de apagar.
--
-- PERDA DE DADOS: apaga todas as contas a pagar e pagamentos registrados
-- (payables, payable_payments). Os recebimentos de estoque em si permanecem
-- em stock_movements — a mercadoria entrou de fato. Faca dump antes de rodar
-- em ambiente com dados reais.

-- Restaura receive_purchase_order sem o upsert de payables (corpo identico
-- ao de 0044 — mesma assinatura, sem armadilha de aridade).
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

    v_cost := COALESCE(
      (v_item->>'unit_cost_cents')::integer,
      v_po_item.unit_cost_cents
    );
    IF v_cost < 0 THEN
      RAISE EXCEPTION 'Custo recebido invalido.'
        USING ERRCODE = 'check_violation';
    END IF;

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
  END LOOP;

  SELECT bool_and(quantity_received >= quantity_ordered) INTO v_all_done
  FROM purchase_order_items
  WHERE purchase_order_id = p_order_id;

  v_new_status := CASE WHEN v_all_done THEN 'received' ELSE 'partially_received' END;

  UPDATE purchase_orders
  SET status = v_new_status,
      received_at = CASE WHEN v_all_done THEN now() ELSE received_at END
  WHERE id = p_order_id;

  PERFORM log_audit(
    v_tenant_id, 'purchase_order.received', 'purchase_orders', p_order_id::text,
    NULL,
    jsonb_build_object(
      'items_received', v_received,
      'status', v_new_status,
      'fully_received', v_all_done
    )
  );

  RETURN jsonb_build_object(
    'status', v_new_status,
    'fully_received', v_all_done,
    'items_received', v_received
  );
END;
$$;

DROP FUNCTION IF EXISTS list_payables(text);
DROP FUNCTION IF EXISTS register_payable_payment(uuid, text, integer, text, text);
DROP FUNCTION IF EXISTS _sf_upsert_payable_on_receipt(uuid, uuid, uuid, bigint, bigint);

DROP POLICY IF EXISTS "payable_payments_select" ON payable_payments;
DROP POLICY IF EXISTS "payables_select" ON payables;

DROP TABLE IF EXISTS payable_payments;

DROP TRIGGER IF EXISTS trg_payables_updated_at ON payables;
DROP TABLE IF EXISTS payables;

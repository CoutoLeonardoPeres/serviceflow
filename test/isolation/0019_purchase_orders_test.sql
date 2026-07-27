-- =============================================================================
-- Testes de isolamento RLS — migration 0044_suppliers_purchase_orders
--
-- Prova o contrato do F3-P3:
--   * o pedido NAO movimenta estoque; so o recebimento movimenta;
--   * o custo que entra no medio e o da nota, nao o cotado;
--   * recebimento parcial mantem o pedido aberto e o saldo pendente correto;
--   * receber acima do pedido e bloqueado;
--   * pedido com recebimento parcial nao pode ser cancelado;
--   * mutacao de pedido/itens so acontece via RPC;
--   * isolamento entre tenants.
--
-- Como executar:
--   psql $DATABASE_URL -f test/isolation/0019_purchase_orders_test.sql
-- Substitua os \set abaixo pelos UUIDs reais do seed antes de executar.
-- =============================================================================

\set ON_ERROR_STOP on

\set TENANT_ALPHA  'a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1'
\set USER_ALPHA    'a1000000-0000-4000-8000-000000000001'
\set USER_BETA     'b2000000-0000-4000-8000-000000000002'
\set USER_TECH     'a1000000-0000-4000-8000-000000000003'
\set USER_VIEWER   'a1000000-0000-4000-8000-000000000004'

DO $$
DECLARE
  v_supplier uuid;
  v_wh       uuid;
  v_prod     uuid;
  v_prod2    uuid;
  v_order    jsonb;
  v_order_id uuid;
  v_item1    uuid;
  v_item2    uuid;
  v_res      jsonb;
  v_status   text;
  v_qty      numeric;
  v_value    bigint;
  v_avg      integer;
  v_count    int;
BEGIN
  RAISE NOTICE '=== F3-P3 Pedidos de compra — Inicio ===';

  -- SETUP
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  INSERT INTO warehouses (tenant_id, name, is_default)
  VALUES (:'TENANT_ALPHA', 'Deposito Compras Teste', true)
  RETURNING id INTO v_wh;

  INSERT INTO products (tenant_id, sku, name, unit)
  VALUES (:'TENANT_ALPHA', 'SKU-CMP-1', 'Cabo comprado', 'm')
  RETURNING id INTO v_prod;

  INSERT INTO products (tenant_id, sku, name, unit)
  VALUES (:'TENANT_ALPHA', 'SKU-CMP-2', 'Disjuntor comprado', 'un')
  RETURNING id INTO v_prod2;

  INSERT INTO suppliers (tenant_id, name, document)
  VALUES (:'TENANT_ALPHA', 'Fornecedor Teste Alpha', '11222333000144')
  RETURNING id INTO v_supplier;

  -- Saldo inicial para provar que o custo medio se altera no recebimento:
  -- 100 m a 200 centavos => medio 200
  PERFORM record_stock_entry(v_prod, v_wh, 100, 200, 'saldo anterior');

  -- ─────────────────────────────────────────────────────────────────────────
  -- T1: criar pedido — nao movimenta estoque
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT create_purchase_order(
    v_supplier, v_wh,
    jsonb_build_array(
      jsonb_build_object('product_id', v_prod,  'quantity', 100, 'unit_cost_cents', 400),
      jsonb_build_object('product_id', v_prod2, 'quantity', 10,  'unit_cost_cents', 5000)
    ),
    NULL, 'pedido de teste'
  ) INTO v_order;

  v_order_id := (v_order->>'id')::uuid;

  IF (v_order->>'total_cents')::bigint <> 90000 THEN
    RAISE EXCEPTION 'FALHOU T1: total do pedido incorreto (%)', v_order->>'total_cents';
  END IF;

  SELECT quantity INTO v_qty FROM stock_balances
  WHERE warehouse_id = v_wh AND product_id = v_prod;
  IF v_qty <> 100 THEN
    RAISE EXCEPTION 'FALHOU T1: criar pedido mexeu no estoque (qtd=%)', v_qty;
  END IF;
  RAISE NOTICE 'PASSOU T1: pedido criado (total 90000) sem tocar no estoque';

  SELECT id INTO v_item1 FROM purchase_order_items
  WHERE purchase_order_id = v_order_id AND product_id = v_prod;
  SELECT id INTO v_item2 FROM purchase_order_items
  WHERE purchase_order_id = v_order_id AND product_id = v_prod2;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T2: rascunho nao aceita recebimento
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM receive_purchase_order(
      v_order_id,
      jsonb_build_array(jsonb_build_object('item_id', v_item1, 'quantity', 10))
    );
    RAISE EXCEPTION 'FALHOU T2: rascunho aceitou recebimento';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T2: rascunho nao aceita recebimento';
  END;

  PERFORM send_purchase_order(v_order_id);

  SELECT status INTO v_status FROM purchase_orders WHERE id = v_order_id;
  IF v_status <> 'sent' THEN
    RAISE EXCEPTION 'FALHOU T2b: pedido nao ficou como enviado (%)', v_status;
  END IF;
  RAISE NOTICE 'PASSOU T2b: pedido enviado';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T3: recebimento parcial entra no estoque e mantem o pedido aberto
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT receive_purchase_order(
    v_order_id,
    jsonb_build_array(jsonb_build_object('item_id', v_item1, 'quantity', 100))
  ) INTO v_res;

  IF (v_res->>'fully_received')::boolean THEN
    RAISE EXCEPTION 'FALHOU T3: pedido marcado como totalmente recebido cedo demais';
  END IF;

  IF v_res->>'status' <> 'partially_received' THEN
    RAISE EXCEPTION 'FALHOU T3: status esperado partially_received, obtido %',
      v_res->>'status';
  END IF;
  RAISE NOTICE 'PASSOU T3: recebimento parcial mantem o pedido aberto';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T4: o custo da NOTA entra no custo medio
  --     (100 * 200 + 100 * 400) / 200 = 300
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT quantity, total_value_cents INTO v_qty, v_value
  FROM stock_balances WHERE warehouse_id = v_wh AND product_id = v_prod;

  IF v_qty <> 200 THEN
    RAISE EXCEPTION 'FALHOU T4: saldo esperado 200, obtido %', v_qty;
  END IF;

  v_avg := stock_average_unit_cost_cents(v_qty, v_value);
  IF v_avg <> 300 THEN
    RAISE EXCEPTION 'FALHOU T4: custo medio esperado 300, obtido %', v_avg;
  END IF;
  RAISE NOTICE 'PASSOU T4: custo do recebimento entrou no medio ponderado';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T5: receber acima do pedido e bloqueado
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM receive_purchase_order(
      v_order_id,
      jsonb_build_array(jsonb_build_object('item_id', v_item1, 'quantity', 1))
    );
    RAISE EXCEPTION 'FALHOU T5: recebeu acima da quantidade pedida';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T5: recebimento acima do pedido bloqueado';
  END;

  -- Saldo intacto apos a tentativa
  SELECT quantity INTO v_qty FROM stock_balances
  WHERE warehouse_id = v_wh AND product_id = v_prod;
  IF v_qty <> 200 THEN
    RAISE EXCEPTION 'FALHOU T5b: saldo alterado por recebimento rejeitado (%)', v_qty;
  END IF;
  RAISE NOTICE 'PASSOU T5b: recebimento rejeitado nao deixou rastro';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T6: pedido parcialmente recebido nao pode ser cancelado
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM cancel_purchase_order(v_order_id, 'tentativa apos recebimento');
    RAISE EXCEPTION 'FALHOU T6: cancelou pedido com mercadoria ja recebida';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T6: pedido parcialmente recebido nao e cancelavel';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T7: preco da nota diferente do cotado prevalece
  --     item2: cotado 5000; recebe 10 a 6000
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT receive_purchase_order(
    v_order_id,
    jsonb_build_array(
      jsonb_build_object('item_id', v_item2, 'quantity', 10, 'unit_cost_cents', 6000)
    )
  ) INTO v_res;

  IF NOT (v_res->>'fully_received')::boolean THEN
    RAISE EXCEPTION 'FALHOU T7: pedido deveria estar totalmente recebido';
  END IF;

  SELECT quantity, total_value_cents INTO v_qty, v_value
  FROM stock_balances WHERE warehouse_id = v_wh AND product_id = v_prod2;

  IF v_qty <> 10 OR v_value <> 60000 THEN
    RAISE EXCEPTION
      'FALHOU T7: preco da nota nao prevaleceu (qtd=%, valor=%)', v_qty, v_value;
  END IF;
  RAISE NOTICE 'PASSOU T7: preco da nota prevaleceu sobre o cotado';

  SELECT status INTO v_status FROM purchase_orders WHERE id = v_order_id;
  IF v_status <> 'received' THEN
    RAISE EXCEPTION 'FALHOU T7b: status final esperado received, obtido %', v_status;
  END IF;
  RAISE NOTICE 'PASSOU T7b: pedido fechado como recebido';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T8: pedido recebido nao aceita mais recebimento
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM receive_purchase_order(
      v_order_id,
      jsonb_build_array(jsonb_build_object('item_id', v_item1, 'quantity', 1))
    );
    RAISE EXCEPTION 'FALHOU T8: pedido fechado aceitou novo recebimento';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T8: pedido recebido nao aceita mais recebimento';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T9: movimentos apontam para o pedido
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT COUNT(*) INTO v_count
  FROM stock_movements
  WHERE related_entity = 'purchase_orders'
    AND related_entity_id = v_order_id
    AND kind = 'in';
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'FALHOU T9: esperado 2 entradas ligadas ao pedido, obtido %', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T9: entradas rastreaveis ate o pedido';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T10: pedidos e itens nao sao gravaveis direto — so via RPC
  -- ─────────────────────────────────────────────────────────────────────────
  UPDATE purchase_orders SET status = 'draft' WHERE id = v_order_id;
  IF FOUND THEN
    RAISE EXCEPTION 'FALHOU T10: status do pedido alterado sem passar por RPC';
  END IF;

  UPDATE purchase_order_items SET quantity_received = 0 WHERE id = v_item1;
  IF FOUND THEN
    RAISE EXCEPTION 'FALHOU T10: item do pedido alterado sem passar por RPC';
  END IF;
  RAISE NOTICE 'PASSOU T10: pedido e itens so mudam via RPC';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T11: viewer le, mas nao cria pedido
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_VIEWER')::text, true);

  SELECT COUNT(*) INTO v_count FROM purchase_orders WHERE id = v_order_id;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FALHOU T11a: viewer com purchases.read nao leu o pedido';
  END IF;

  BEGIN
    PERFORM create_purchase_order(
      v_supplier, v_wh,
      jsonb_build_array(
        jsonb_build_object('product_id', v_prod, 'quantity', 1, 'unit_cost_cents', 100)
      ),
      NULL, NULL
    );
    RAISE EXCEPTION 'FALHOU T11: viewer sem purchases.write criou pedido';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T11: viewer le mas nao cria pedido';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T12: tecnico recebe, mas nao cria pedido
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_TECH')::text, true);

  BEGIN
    PERFORM create_purchase_order(
      v_supplier, v_wh,
      jsonb_build_array(
        jsonb_build_object('product_id', v_prod, 'quantity', 1, 'unit_cost_cents', 100)
      ),
      NULL, NULL
    );
    RAISE EXCEPTION 'FALHOU T12: tecnico sem purchases.write criou pedido';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T12: tecnico nao cria pedido de compra';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T13: isolamento — beta nao ve fornecedor nem pedido do alpha
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_BETA')::text, true);

  SELECT COUNT(*) INTO v_count FROM suppliers WHERE id = v_supplier;
  IF v_count > 0 THEN
    RAISE EXCEPTION 'FALHOU T13: beta_owner viu fornecedor do tenant alpha';
  END IF;

  SELECT COUNT(*) INTO v_count FROM purchase_orders WHERE id = v_order_id;
  IF v_count > 0 THEN
    RAISE EXCEPTION 'FALHOU T13: beta_owner viu pedido do tenant alpha';
  END IF;

  SELECT COUNT(*) INTO v_count FROM purchase_order_items WHERE purchase_order_id = v_order_id;
  IF v_count > 0 THEN
    RAISE EXCEPTION 'FALHOU T13: beta_owner viu itens do pedido do alpha';
  END IF;
  RAISE NOTICE 'PASSOU T13: beta_owner nao ve compras do alpha';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T14: beta nao cria pedido citando fornecedor do alpha
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM create_purchase_order(
      v_supplier, v_wh,
      jsonb_build_array(
        jsonb_build_object('product_id', v_prod, 'quantity', 1, 'unit_cost_cents', 100)
      ),
      NULL, NULL
    );
    RAISE EXCEPTION 'FALHOU T14: beta_owner criou pedido com fornecedor do alpha';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T14: beta_owner nao usa fornecedor do alpha';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T15: cancelamento exige motivo e so vale para rascunho/enviado
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  DECLARE
    v_order2 jsonb;
    v_order2_id uuid;
  BEGIN
    SELECT create_purchase_order(
      v_supplier, v_wh,
      jsonb_build_array(
        jsonb_build_object('product_id', v_prod, 'quantity', 5, 'unit_cost_cents', 100)
      ),
      NULL, NULL
    ) INTO v_order2;
    v_order2_id := (v_order2->>'id')::uuid;

    BEGIN
      PERFORM cancel_purchase_order(v_order2_id, NULL);
      RAISE EXCEPTION 'FALHOU T15: cancelamento aceito sem motivo';
    EXCEPTION
      WHEN check_violation THEN
        RAISE NOTICE 'PASSOU T15a: cancelamento sem motivo rejeitado';
    END;

    PERFORM cancel_purchase_order(v_order2_id, 'fornecedor sem estoque');

    SELECT status INTO v_status FROM purchase_orders WHERE id = v_order2_id;
    IF v_status <> 'cancelled' THEN
      RAISE EXCEPTION 'FALHOU T15b: pedido nao foi cancelado (%)', v_status;
    END IF;
    RAISE NOTICE 'PASSOU T15b: rascunho cancelado com motivo';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T16: list_purchase_order_items calcula a pendencia
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT COUNT(*) INTO v_count
  FROM list_purchase_order_items(v_order_id)
  WHERE quantity_pending = 0;
  IF v_count <> 2 THEN
    RAISE EXCEPTION
      'FALHOU T16: esperado 2 itens sem pendencia, obtido %', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T16: pendencia por item calculada corretamente';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T17: auditoria do ciclo
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SELECT COUNT(*) INTO v_count
  FROM audit_logs
  WHERE tenant_id = :'TENANT_ALPHA'
    AND action IN (
      'purchase_order.created','purchase_order.sent',
      'purchase_order.received','purchase_order.cancelled'
    );
  IF v_count < 4 THEN
    RAISE EXCEPTION 'FALHOU T17: ciclo do pedido nao auditado (count=%)', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T17: % evento(s) de auditoria do ciclo de compra', v_count;

  RAISE NOTICE '=== Testes F3-P3 (compras) concluidos ===';
  RAISE EXCEPTION 'ROLLBACK_TEST_DATA' USING DETAIL = 'Dados de teste removidos.';

EXCEPTION
  WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM = 'ROLLBACK_TEST_DATA' THEN
      RAISE NOTICE 'Dados de teste revertidos (rollback intencional).';
    ELSE
      RAISE;
    END IF;
END;
$$;

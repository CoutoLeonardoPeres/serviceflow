-- =============================================================================
-- Testes de isolamento RLS — migration 0045_transfers_counts_multi_warehouse
--
-- O caso central aqui e a CONSERVACAO DE VALOR na transferencia: o valor total
-- do estoque tem que ser identico antes e depois, ate o centavo. T3 e T4 usam
-- numeros propositalmente quebrados para pegar erro de arredondamento — que e
-- exatamente o bug que apareceria se a transferencia usasse saida + entrada
-- pelos RPCs comuns.
--
-- Como executar:
--   psql $DATABASE_URL -f test/isolation/0020_transfers_counts_test.sql
-- Substitua os \set abaixo pelos UUIDs reais do seed antes de executar.
-- =============================================================================

\set ON_ERROR_STOP on

\set TENANT_ALPHA  'a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1'
\set USER_ALPHA    'a1000000-0000-4000-8000-000000000001'
\set USER_BETA     'b2000000-0000-4000-8000-000000000002'
\set USER_TECH     'a1000000-0000-4000-8000-000000000003'

DO $$
DECLARE
  v_wh_a     uuid;
  v_wh_b     uuid;
  v_prod     uuid;
  v_res      jsonb;
  v_count    jsonb;
  v_count_id uuid;
  v_item_id  uuid;
  v_qty_a    numeric;
  v_qty_b    numeric;
  v_val_a    bigint;
  v_val_b    bigint;
  v_total_before bigint;
  v_total_after  bigint;
  v_n        int;
BEGIN
  RAISE NOTICE '=== F3-P4 Transferencias e inventario — Inicio ===';

  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  INSERT INTO warehouses (tenant_id, name, is_default)
  VALUES (:'TENANT_ALPHA', 'Deposito A Teste', true)
  RETURNING id INTO v_wh_a;

  INSERT INTO warehouses (tenant_id, name)
  VALUES (:'TENANT_ALPHA', 'Deposito B Teste')
  RETURNING id INTO v_wh_b;

  INSERT INTO products (tenant_id, sku, name, unit)
  VALUES (:'TENANT_ALPHA', 'SKU-TRF-1', 'Produto transferivel', 'un')
  RETURNING id INTO v_prod;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T1: origem e destino iguais e rejeitado
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM transfer_stock(
      v_wh_a, v_wh_a,
      jsonb_build_array(jsonb_build_object('product_id', v_prod, 'quantity', 1)),
      'invalida'
    );
    RAISE EXCEPTION 'FALHOU T1: transferencia para o mesmo deposito aceita';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T1: origem igual ao destino rejeitada';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T2: sem saldo na origem, transferencia e rejeitada
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM transfer_stock(
      v_wh_a, v_wh_b,
      jsonb_build_array(jsonb_build_object('product_id', v_prod, 'quantity', 10)),
      'sem saldo'
    );
    RAISE EXCEPTION 'FALHOU T2: transferiu sem saldo';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T2: transferencia sem saldo rejeitada';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T3: CONSERVACAO DE VALOR com numero quebrado
  --     3 un a 3333 centavos => valor 9999, medio 3333 (nao divisivel)
  --     transfere 1: origem perde round(9999*1/3)=3333, destino ganha 3333
  -- ─────────────────────────────────────────────────────────────────────────
  PERFORM record_stock_entry(v_prod, v_wh_a, 3, 3333, 'carga quebrada');

  SELECT COALESCE(SUM(total_value_cents), 0) INTO v_total_before
  FROM stock_balances WHERE product_id = v_prod;

  PERFORM transfer_stock(
    v_wh_a, v_wh_b,
    jsonb_build_array(jsonb_build_object('product_id', v_prod, 'quantity', 1)),
    'transferencia quebrada'
  );

  SELECT COALESCE(SUM(total_value_cents), 0) INTO v_total_after
  FROM stock_balances WHERE product_id = v_prod;

  IF v_total_before <> v_total_after THEN
    RAISE EXCEPTION
      'FALHOU T3: valor total mudou na transferencia (antes %, depois %)',
      v_total_before, v_total_after;
  END IF;
  RAISE NOTICE 'PASSOU T3: valor total preservado (% centavos)', v_total_after;

  SELECT quantity, total_value_cents INTO v_qty_a, v_val_a
  FROM stock_balances WHERE warehouse_id = v_wh_a AND product_id = v_prod;
  SELECT quantity, total_value_cents INTO v_qty_b, v_val_b
  FROM stock_balances WHERE warehouse_id = v_wh_b AND product_id = v_prod;

  IF v_qty_a <> 2 OR v_qty_b <> 1 THEN
    RAISE EXCEPTION 'FALHOU T3b: quantidades erradas (A=%, B=%)', v_qty_a, v_qty_b;
  END IF;

  IF v_val_a + v_val_b <> 9999 THEN
    RAISE EXCEPTION
      'FALHOU T3c: soma dos valores diverge (A=%, B=%, total=%)',
      v_val_a, v_val_b, v_val_a + v_val_b;
  END IF;
  RAISE NOTICE 'PASSOU T3b/c: A=% (%), B=% (%) — soma exata',
    v_qty_a, v_val_a, v_qty_b, v_val_b;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T4: transferir TODO o saldo restante leva o valor inteiro, sem residuo
  -- ─────────────────────────────────────────────────────────────────────────
  PERFORM transfer_stock(
    v_wh_a, v_wh_b,
    jsonb_build_array(jsonb_build_object('product_id', v_prod, 'quantity', 2)),
    'zera origem'
  );

  SELECT quantity, total_value_cents INTO v_qty_a, v_val_a
  FROM stock_balances WHERE warehouse_id = v_wh_a AND product_id = v_prod;

  IF v_qty_a <> 0 OR v_val_a <> 0 THEN
    RAISE EXCEPTION
      'FALHOU T4: origem zerada deixou residuo (qtd=%, valor=%)', v_qty_a, v_val_a;
  END IF;

  SELECT total_value_cents INTO v_val_b
  FROM stock_balances WHERE warehouse_id = v_wh_b AND product_id = v_prod;

  IF v_val_b <> 9999 THEN
    RAISE EXCEPTION
      'FALHOU T4b: destino nao recebeu o valor integral (%)', v_val_b;
  END IF;
  RAISE NOTICE 'PASSOU T4: origem zerada sem residuo, destino com 9999';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T5: transferencia gera par de movimentos ligados
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT COUNT(*) INTO v_n
  FROM stock_transfer_items
  WHERE out_movement_id IS NOT NULL AND in_movement_id IS NOT NULL;
  IF v_n < 2 THEN
    RAISE EXCEPTION 'FALHOU T5: itens sem par de movimentos (count=%)', v_n;
  END IF;

  SELECT COUNT(*) INTO v_n
  FROM stock_movements WHERE related_entity = 'stock_transfers';
  IF v_n <> 4 THEN
    RAISE EXCEPTION
      'FALHOU T5b: esperado 4 movimentos de transferencia, obtido %', v_n;
  END IF;
  RAISE NOTICE 'PASSOU T5: movimentos de transferencia pareados e rastreaveis';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T6: tecnico (stock.write, sem stock.adjust) transfere mas nao inventaria
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_TECH')::text, true);

  PERFORM transfer_stock(
    v_wh_b, v_wh_a,
    jsonb_build_array(jsonb_build_object('product_id', v_prod, 'quantity', 1)),
    'tecnico devolvendo'
  );
  RAISE NOTICE 'PASSOU T6a: tecnico com stock.write transfere';

  BEGIN
    PERFORM create_stock_count(v_wh_a, NULL, 'tentativa do tecnico');
    RAISE EXCEPTION 'FALHOU T6: tecnico sem stock.adjust abriu contagem';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T6b: tecnico sem stock.adjust nao abre contagem';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T7: contagem abre com os itens do deposito e o saldo do sistema
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  SELECT create_stock_count(v_wh_a, NULL, 'inventario de teste') INTO v_count;
  v_count_id := (v_count->>'id')::uuid;

  IF (v_count->>'items')::int < 1 THEN
    RAISE EXCEPTION 'FALHOU T7: contagem aberta sem itens';
  END IF;

  SELECT id INTO v_item_id
  FROM stock_count_items WHERE count_id = v_count_id AND product_id = v_prod;
  IF v_item_id IS NULL THEN
    RAISE EXCEPTION 'FALHOU T7b: produto com saldo ficou fora da contagem';
  END IF;
  RAISE NOTICE 'PASSOU T7: contagem aberta com itens do deposito';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T8: registrar contagem divergente e aplicar gera ajuste
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT quantity INTO v_qty_a
  FROM stock_balances WHERE warehouse_id = v_wh_a AND product_id = v_prod;

  PERFORM set_stock_count_quantity(v_item_id, v_qty_a + 5);

  SELECT apply_stock_count(v_count_id) INTO v_res;

  IF (v_res->>'adjusted')::int <> 1 THEN
    RAISE EXCEPTION
      'FALHOU T8: esperado 1 ajuste, obtido %', v_res->>'adjusted';
  END IF;

  SELECT quantity INTO v_qty_b
  FROM stock_balances WHERE warehouse_id = v_wh_a AND product_id = v_prod;
  IF v_qty_b <> v_qty_a + 5 THEN
    RAISE EXCEPTION
      'FALHOU T8b: saldo nao virou a quantidade contada (% vs %)',
      v_qty_b, v_qty_a + 5;
  END IF;

  SELECT COUNT(*) INTO v_n
  FROM stock_movements
  WHERE kind = 'adjustment' AND reason LIKE 'Inventario #%';
  IF v_n < 1 THEN
    RAISE EXCEPTION 'FALHOU T8c: ajuste da contagem nao virou movimento';
  END IF;
  RAISE NOTICE 'PASSOU T8: contagem aplicada gerou ajuste rastreavel';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T9: contagem aplicada nao aceita alteracao nem reaplicacao
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM set_stock_count_quantity(v_item_id, 1);
    RAISE EXCEPTION 'FALHOU T9: contagem aplicada aceitou alteracao';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T9a: contagem aplicada nao aceita alteracao';
  END;

  BEGIN
    PERFORM apply_stock_count(v_count_id);
    RAISE EXCEPTION 'FALHOU T9: contagem aplicada duas vezes';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T9b: contagem nao e aplicada duas vezes';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T10: item sem divergencia nao gera ajuste
  -- ─────────────────────────────────────────────────────────────────────────
  DECLARE
    v_count2    jsonb;
    v_count2_id uuid;
    v_item2     uuid;
  BEGIN
    SELECT create_stock_count(v_wh_a, NULL, 'segunda contagem') INTO v_count2;
    v_count2_id := (v_count2->>'id')::uuid;

    SELECT id INTO v_item2
    FROM stock_count_items WHERE count_id = v_count2_id AND product_id = v_prod;

    SELECT quantity INTO v_qty_a
    FROM stock_balances WHERE warehouse_id = v_wh_a AND product_id = v_prod;

    -- Conta exatamente o que o sistema diz.
    PERFORM set_stock_count_quantity(v_item2, v_qty_a);

    SELECT apply_stock_count(v_count2_id) INTO v_res;

    IF (v_res->>'adjusted')::int <> 0 THEN
      RAISE EXCEPTION
        'FALHOU T10: gerou ajuste para item sem divergencia (%)',
        v_res->>'adjusted';
    END IF;
    RAISE NOTICE 'PASSOU T10: item conferido sem divergencia nao gera ajuste';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T11: consumo da OS aceita deposito escolhido
  -- ─────────────────────────────────────────────────────────────────────────
  DECLARE
    v_customer uuid;
    v_request  uuid;
    v_quote    jsonb;
    v_wo       jsonb;
    v_wo_id    uuid;
    v_mat      jsonb;
    v_wh_used  uuid;
  BEGIN
    INSERT INTO customers (tenant_id, type, name, is_active)
    VALUES (:'TENANT_ALPHA', 'company', 'Cliente Multi Deposito', true)
    RETURNING id INTO v_customer;

    INSERT INTO service_requests (
      tenant_id, number, customer_id, title, description, channel, status
    ) VALUES (
      :'TENANT_ALPHA', 9941, v_customer, 'Chamado Multi Deposito',
      'Descricao suficiente para teste de multi deposito.', 'phone', 'opened'
    ) RETURNING id INTO v_request;

    SELECT create_quotation(
      v_customer, v_request, '2026-08-20', 'multi deposito', NULL,
      '[{"kind":"service","description":"Servico","quantity":1,"unit_price_cents":10000,"unit_cost_cents":4000}]'::jsonb
    ) INTO v_quote;

    RESET role;
    UPDATE quotations SET status = 'approved' WHERE id = (v_quote->>'id')::uuid;

    SET LOCAL role = authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);
    SELECT convert_approved_quotation_to_work_order((v_quote->>'id')::uuid) INTO v_wo;
    v_wo_id := (v_wo->>'id')::uuid;

    -- Ha saldo no deposito B, nao no padrao A? Garante saldo em B:
    PERFORM record_stock_entry(v_prod, v_wh_b, 10, 1000, 'saldo em B');

    SELECT add_work_order_material(
      v_wo_id, NULL, 2, 0, 3000, v_prod, v_wh_b
    ) INTO v_mat;

    IF NOT (v_mat->>'from_stock')::boolean THEN
      RAISE EXCEPTION 'FALHOU T11: consumo com deposito explicito nao baixou';
    END IF;

    SELECT warehouse_id INTO v_wh_used
    FROM work_order_materials WHERE id = (v_mat->>'id')::uuid;

    IF v_wh_used <> v_wh_b THEN
      RAISE EXCEPTION
        'FALHOU T11b: baixa saiu do deposito errado (esperado B)';
    END IF;
    RAISE NOTICE 'PASSOU T11: OS baixou do deposito escolhido, nao do padrao';

    -- Deposito inexistente e rejeitado
    BEGIN
      PERFORM add_work_order_material(
        v_wo_id, NULL, 1, 0, 1000, v_prod,
        '00000000-0000-4000-8000-000000000000'::uuid
      );
      RAISE EXCEPTION 'FALHOU T11c: deposito invalido aceito';
    EXCEPTION
      WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASSOU T11c: deposito invalido rejeitado';
    END;
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T12: isolamento — beta nao ve nem cria transferencia/contagem do alpha
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_BETA')::text, true);

  SELECT COUNT(*) INTO v_n FROM stock_transfers;
  IF v_n > 0 THEN
    RAISE EXCEPTION 'FALHOU T12: beta_owner viu transferencias do alpha';
  END IF;

  SELECT COUNT(*) INTO v_n FROM stock_counts;
  IF v_n > 0 THEN
    RAISE EXCEPTION 'FALHOU T12: beta_owner viu contagens do alpha';
  END IF;

  BEGIN
    PERFORM transfer_stock(
      v_wh_a, v_wh_b,
      jsonb_build_array(jsonb_build_object('product_id', v_prod, 'quantity', 1)),
      'cross tenant'
    );
    RAISE EXCEPTION 'FALHOU T12: beta_owner transferiu estoque do alpha';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T12: beta_owner isolado de transferencias e contagens';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T13: tabelas de transferencia e contagem nao sao gravaveis direto
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  UPDATE stock_transfers SET reason = 'adulterado';
  IF FOUND THEN
    RAISE EXCEPTION 'FALHOU T13: transferencia alterada sem passar por RPC';
  END IF;

  DELETE FROM stock_transfer_items;
  IF FOUND THEN
    RAISE EXCEPTION 'FALHOU T13: item de transferencia apagado direto';
  END IF;
  RAISE NOTICE 'PASSOU T13: transferencias so mudam via RPC';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T14: auditoria de transferencia e inventario
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SELECT COUNT(*) INTO v_n
  FROM audit_logs
  WHERE tenant_id = :'TENANT_ALPHA'
    AND action IN ('stock.transfer','stock.count.created','stock.count.applied');
  IF v_n < 3 THEN
    RAISE EXCEPTION 'FALHOU T14: eventos nao auditados (count=%)', v_n;
  END IF;
  RAISE NOTICE 'PASSOU T14: % evento(s) de auditoria de transferencia/inventario', v_n;

  RAISE NOTICE '=== Testes F3-P4 concluidos ===';
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

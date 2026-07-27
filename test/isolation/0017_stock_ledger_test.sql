-- =============================================================================
-- Testes de isolamento RLS — migration 0042_stock_ledger
--
-- Alem do isolamento entre tenants, este arquivo prova as invariantes do razao:
--   * saldo nunca fica negativo;
--   * custo medio ponderado movel bate com o calculo manual (ADR-020);
--   * o residuo de arredondamento nao some nem se acumula;
--   * movimentos sao imutaveis mesmo para o owner;
--   * ajuste de inventario exige stock.adjust, mais restrito que stock.write.
--
-- Como executar:
--   psql $DATABASE_URL -f test/isolation/0017_stock_ledger_test.sql
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
  v_wh_alpha   uuid;
  v_prod_alpha uuid;
  v_prod_nostk uuid;
  v_res        jsonb;
  v_qty        numeric;
  v_value      bigint;
  v_avg        integer;
  v_count      int;
BEGIN
  RAISE NOTICE '=== F3 RLS Razao de Estoque — Inicio ===';

  -- SETUP
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  INSERT INTO warehouses (tenant_id, name, is_default)
  VALUES (:'TENANT_ALPHA', 'Deposito Central Teste', true)
  RETURNING id INTO v_wh_alpha;

  INSERT INTO products (tenant_id, sku, name, unit, min_quantity)
  VALUES (:'TENANT_ALPHA', 'SKU-TESTE-1', 'Cabo Flexivel 2.5mm', 'm', 10)
  RETURNING id INTO v_prod_alpha;

  INSERT INTO products (tenant_id, sku, name, track_stock)
  VALUES (:'TENANT_ALPHA', 'SKU-SERVICO', 'Servico sem estoque', false)
  RETURNING id INTO v_prod_nostk;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T1: entrada inicial — 100 un a 250 centavos
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT record_stock_entry(v_prod_alpha, v_wh_alpha, 100, 250, 'compra inicial')
  INTO v_res;

  IF (v_res->>'quantity')::numeric <> 100
     OR (v_res->>'total_value_cents')::bigint <> 25000
     OR (v_res->>'average_unit_cost_cents')::int <> 250 THEN
    RAISE EXCEPTION 'FALHOU T1: saldo apos entrada incorreto: %', v_res;
  END IF;
  RAISE NOTICE 'PASSOU T1: entrada 100 x 250 => qtd 100, valor 25000, medio 250';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T2: custo medio ponderado movel — segunda entrada a preco diferente
  --     (100 * 250 + 100 * 350) / 200 = 300
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT record_stock_entry(v_prod_alpha, v_wh_alpha, 100, 350, 'segunda compra')
  INTO v_res;

  IF (v_res->>'quantity')::numeric <> 200
     OR (v_res->>'total_value_cents')::bigint <> 60000
     OR (v_res->>'average_unit_cost_cents')::int <> 300 THEN
    RAISE EXCEPTION 'FALHOU T2: custo medio ponderado incorreto: %', v_res;
  END IF;
  RAISE NOTICE 'PASSOU T2: medio ponderado = 300 apos entradas de 250 e 350';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T3: saida baixa pelo custo medio e nao altera o medio
  --     saida de 50 => valor baixado 15000; restam 150 un e 45000
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT record_stock_exit(v_prod_alpha, v_wh_alpha, 50, 'consumo em campo')
  INTO v_res;

  IF (v_res->>'quantity')::numeric <> 150
     OR (v_res->>'total_value_cents')::bigint <> 45000
     OR (v_res->>'average_unit_cost_cents')::int <> 300 THEN
    RAISE EXCEPTION 'FALHOU T3: saida alterou o custo medio: %', v_res;
  END IF;
  RAISE NOTICE 'PASSOU T3: saida baixou pelo medio sem altera-lo';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T4: INVARIANTE — saida maior que o saldo e rejeitada
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM record_stock_exit(v_prod_alpha, v_wh_alpha, 999, 'saida impossivel');
    RAISE EXCEPTION 'FALHOU T4: saldo ficou negativo';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T4: saida acima do saldo rejeitada';
  END;

  -- Saldo intacto apos a tentativa
  SELECT quantity INTO v_qty FROM stock_balances
  WHERE warehouse_id = v_wh_alpha AND product_id = v_prod_alpha;
  IF v_qty <> 150 THEN
    RAISE EXCEPTION 'FALHOU T4b: saldo alterado por saida rejeitada (qtd=%)', v_qty;
  END IF;
  RAISE NOTICE 'PASSOU T4b: saldo intacto apos saida rejeitada';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T5: produto sem track_stock nao aceita movimento
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM record_stock_entry(v_prod_nostk, v_wh_alpha, 1, 100, 'nao deveria');
    RAISE EXCEPTION 'FALHOU T5: produto sem controle de estoque aceitou movimento';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T5: produto sem track_stock rejeita movimento';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T6: quantidade zero ou negativa e rejeitada
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM record_stock_entry(v_prod_alpha, v_wh_alpha, 0, 100, 'zero');
    RAISE EXCEPTION 'FALHOU T6: entrada de quantidade zero aceita';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T6: quantidade zero rejeitada';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T7: residuo de arredondamento nao some — zerar leva todo o valor
  --     3 un a 100 centavos = 300; saida de 1 baixa 100; saida de 2 zera tudo
  -- ─────────────────────────────────────────────────────────────────────────
  DECLARE
    v_prod_round uuid;
  BEGIN
    INSERT INTO products (tenant_id, sku, name, unit)
    VALUES (:'TENANT_ALPHA', 'SKU-ARRED', 'Produto Arredondamento', 'un')
    RETURNING id INTO v_prod_round;

    -- 3 un a 3333 centavos => valor 9999, medio 3333
    PERFORM record_stock_entry(v_prod_round, v_wh_alpha, 3, 3333, 'entrada quebrada');
    PERFORM record_stock_exit(v_prod_round, v_wh_alpha, 1, 'saida 1');

    SELECT quantity, total_value_cents INTO v_qty, v_value
    FROM stock_balances WHERE warehouse_id = v_wh_alpha AND product_id = v_prod_round;

    IF v_qty <> 2 OR v_value <> 6666 THEN
      RAISE EXCEPTION 'FALHOU T7: baixa proporcional errada (qtd=%, valor=%)', v_qty, v_value;
    END IF;

    -- Zerar: deve levar exatamente o que restou, sem sobra nem falta
    PERFORM record_stock_exit(v_prod_round, v_wh_alpha, 2, 'zera');

    SELECT quantity, total_value_cents INTO v_qty, v_value
    FROM stock_balances WHERE warehouse_id = v_wh_alpha AND product_id = v_prod_round;

    IF v_qty <> 0 OR v_value <> 0 THEN
      RAISE EXCEPTION
        'FALHOU T7: saldo zerado deixou residuo (qtd=%, valor=%)', v_qty, v_value;
    END IF;
    RAISE NOTICE 'PASSOU T7: saldo zerado sem residuo de valor';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T8: tecnico tem stock.write mas NAO stock.adjust
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_TECH')::text, true);

  -- Consegue movimentar
  PERFORM record_stock_exit(v_prod_alpha, v_wh_alpha, 10, 'consumo do tecnico');
  RAISE NOTICE 'PASSOU T8a: tecnico com stock.write registra saida';

  -- Mas nao ajusta inventario
  BEGIN
    PERFORM record_stock_adjustment(v_prod_alpha, v_wh_alpha, 999, 'tentativa de ajuste');
    RAISE EXCEPTION 'FALHOU T8: tecnico sem stock.adjust ajustou inventario';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T8b: tecnico sem stock.adjust nao ajusta inventario';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T9: viewer tem stock.read mas nao stock.write
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_VIEWER')::text, true);

  SELECT COUNT(*) INTO v_count FROM stock_balances WHERE warehouse_id = v_wh_alpha;
  IF v_count < 1 THEN
    RAISE EXCEPTION 'FALHOU T9a: viewer com stock.read nao leu saldos';
  END IF;

  BEGIN
    PERFORM record_stock_entry(v_prod_alpha, v_wh_alpha, 1, 100, 'viewer tentando');
    RAISE EXCEPTION 'FALHOU T9: viewer sem stock.write movimentou estoque';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T9: viewer le saldos mas nao movimenta';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T10: ajuste de inventario exige motivo e registra movimento
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  BEGIN
    PERFORM record_stock_adjustment(v_prod_alpha, v_wh_alpha, 100, NULL);
    RAISE EXCEPTION 'FALHOU T10: ajuste aceito sem motivo';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T10a: ajuste sem motivo rejeitado';
  END;

  SELECT record_stock_adjustment(v_prod_alpha, v_wh_alpha, 100, 'inventario ciclico de julho')
  INTO v_res;
  IF (v_res->>'quantity')::numeric <> 100 THEN
    RAISE EXCEPTION 'FALHOU T10b: ajuste nao aplicou a quantidade contada: %', v_res;
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM stock_movements
  WHERE product_id = v_prod_alpha AND kind = 'adjustment';
  IF v_count < 1 THEN
    RAISE EXCEPTION 'FALHOU T10c: ajuste nao gerou movimento';
  END IF;
  RAISE NOTICE 'PASSOU T10: ajuste com motivo aplicado e registrado';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T11: movimentos sao imutaveis mesmo para o owner
  -- ─────────────────────────────────────────────────────────────────────────
  UPDATE stock_movements SET quantity = 1 WHERE product_id = v_prod_alpha;
  IF FOUND THEN
    RAISE EXCEPTION 'FALHOU T11: movimento de estoque foi alterado';
  END IF;

  DELETE FROM stock_movements WHERE product_id = v_prod_alpha;
  IF FOUND THEN
    RAISE EXCEPTION 'FALHOU T11: movimento de estoque foi apagado';
  END IF;
  RAISE NOTICE 'PASSOU T11: stock_movements imutavel mesmo para o owner';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T12: saldo nao e gravavel direto — so pelos RPCs
  -- ─────────────────────────────────────────────────────────────────────────
  UPDATE stock_balances SET quantity = 99999 WHERE warehouse_id = v_wh_alpha;
  IF FOUND THEN
    RAISE EXCEPTION 'FALHOU T12: saldo alterado direto, sem passar por RPC';
  END IF;
  RAISE NOTICE 'PASSOU T12: stock_balances so muta via RPC';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T13: isolamento — beta nao ve produto, deposito, saldo nem movimento
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_BETA')::text, true);

  SELECT COUNT(*) INTO v_count FROM products WHERE id = v_prod_alpha;
  IF v_count > 0 THEN
    RAISE EXCEPTION 'FALHOU T13: beta_owner viu produto do tenant alpha';
  END IF;

  SELECT COUNT(*) INTO v_count FROM warehouses WHERE id = v_wh_alpha;
  IF v_count > 0 THEN
    RAISE EXCEPTION 'FALHOU T13: beta_owner viu deposito do tenant alpha';
  END IF;

  SELECT COUNT(*) INTO v_count FROM stock_balances WHERE warehouse_id = v_wh_alpha;
  IF v_count > 0 THEN
    RAISE EXCEPTION 'FALHOU T13: beta_owner viu saldo do tenant alpha';
  END IF;

  SELECT COUNT(*) INTO v_count FROM stock_movements WHERE product_id = v_prod_alpha;
  IF v_count > 0 THEN
    RAISE EXCEPTION 'FALHOU T13: beta_owner viu movimentos do tenant alpha';
  END IF;
  RAISE NOTICE 'PASSOU T13: beta_owner nao ve nada do estoque do alpha';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T14: beta nao movimenta estoque do alpha
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM record_stock_entry(v_prod_alpha, v_wh_alpha, 5, 100, 'cross tenant');
    RAISE EXCEPTION 'FALHOU T14: beta_owner movimentou estoque do tenant alpha';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T14: beta_owner nao movimenta estoque do alpha';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T15: list_stock_balances respeita o tenant e o filtro de minimo
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT COUNT(*) INTO v_count FROM list_stock_balances(NULL, false);
  IF v_count > 0 THEN
    RAISE EXCEPTION 'FALHOU T15: list_stock_balances vazou saldos para outro tenant';
  END IF;

  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  SELECT COUNT(*) INTO v_count FROM list_stock_balances(v_wh_alpha, false);
  IF v_count < 1 THEN
    RAISE EXCEPTION 'FALHOU T15: list_stock_balances nao retornou saldos do proprio tenant';
  END IF;
  RAISE NOTICE 'PASSOU T15: list_stock_balances isolado por tenant';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T16: auditoria — entrada, saida e ajuste geraram audit_log
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SELECT COUNT(*) INTO v_count
  FROM audit_logs
  WHERE tenant_id = :'TENANT_ALPHA'
    AND action IN ('stock.entry','stock.exit','stock.adjustment');
  IF v_count < 3 THEN
    RAISE EXCEPTION 'FALHOU T16: movimentos nao auditados (count=%)', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T16: % evento(s) de auditoria de estoque', v_count;

  RAISE NOTICE '=== Testes F3 (razao de estoque) concluidos ===';
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

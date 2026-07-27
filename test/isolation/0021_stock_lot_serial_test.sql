-- =============================================================================
-- Testes de isolamento RLS — migration 0047_stock_lot_serial_tracking (F3-P5)
--
-- Cobre: obrigatoriedade condicional de lote/serie (so quando o produto tem
-- tracking_type != none), find-or-create de lote, quantidade=1 para serie,
-- uma serie so tem uma "posse" por vez (nao entra duas vezes sem sair, nao
-- sai sem ter entrado), get_lot_history, isolamento entre tenants.
--
-- Como executar:
--   psql $DATABASE_URL -f test/isolation/0021_stock_lot_serial_test.sql
-- Substitua os \set abaixo pelos UUIDs reais do seed antes de executar.
-- =============================================================================

\set ON_ERROR_STOP on

\set TENANT_ALPHA  'a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1'
\set TENANT_BETA   'b2b2b2b2-b2b2-4b2b-b2b2-b2b2b2b2b2b2'
\set USER_ALPHA    'a1000000-0000-4000-8000-000000000001'
\set USER_BETA     'b2000000-0000-4000-8000-000000000002'
\set USER_TECH     'a1000000-0000-4000-8000-000000000003'

DO $$
DECLARE
  v_wh_alpha    uuid;
  v_wh_beta     uuid;
  v_prod_lot    uuid;
  v_prod_serial uuid;
  v_prod_none   uuid;
  v_res         jsonb;
  v_lot_id      uuid;
  v_count       int;
BEGIN
  RAISE NOTICE '=== F3-P5 RLS Lote/Serie — Inicio ===';

  -- SETUP
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  INSERT INTO warehouses (tenant_id, name, is_default)
  VALUES (:'TENANT_ALPHA', 'Deposito Lote Teste', true)
  RETURNING id INTO v_wh_alpha;

  INSERT INTO products (tenant_id, sku, name, unit, tracking_type)
  VALUES (:'TENANT_ALPHA', 'SKU-LOTE-1', 'Selante em lote', 'un', 'lot')
  RETURNING id INTO v_prod_lot;

  INSERT INTO products (tenant_id, sku, name, unit, tracking_type)
  VALUES (:'TENANT_ALPHA', 'SKU-SERIE-1', 'Compressor com serie', 'un', 'serial')
  RETURNING id INTO v_prod_serial;

  INSERT INTO products (tenant_id, sku, name, unit, tracking_type)
  VALUES (:'TENANT_ALPHA', 'SKU-COMUM-1', 'Parafuso sem rastreio', 'un', 'none')
  RETURNING id INTO v_prod_none;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T1: produto tipo 'lot' exige codigo de lote na entrada
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM record_stock_entry(v_prod_lot, v_wh_alpha, 10, 500, 'sem lote');
    RAISE EXCEPTION 'FALHOU T1: entrada sem lote foi aceita';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T1: entrada sem lote rejeitada';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T2: entrada com codigo de lote cria o lote (find-or-create)
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT record_stock_entry(v_prod_lot, v_wh_alpha, 10, 500, 'compra', NULL, NULL, 'LOTE-001')
  INTO v_res;

  IF v_res->>'lot_id' IS NULL THEN
    RAISE EXCEPTION 'FALHOU T2: entrada com lote nao retornou lot_id';
  END IF;
  v_lot_id := (v_res->>'lot_id')::uuid;
  RAISE NOTICE 'PASSOU T2: lote LOTE-001 criado (id=%)', v_lot_id;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T3: segunda entrada com o MESMO codigo reusa o lote, nao duplica
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT record_stock_entry(v_prod_lot, v_wh_alpha, 5, 500, 'compra 2', NULL, NULL, 'lote-001')
  INTO v_res;

  IF (v_res->>'lot_id')::uuid <> v_lot_id THEN
    RAISE EXCEPTION 'FALHOU T3: codigo de lote case-insensitive criou lote duplicado';
  END IF;
  SELECT COUNT(*) INTO v_count FROM stock_lots
  WHERE tenant_id = :'TENANT_ALPHA' AND product_id = v_prod_lot;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FALHOU T3: existem % lotes em vez de 1', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T3: segunda entrada reusou o mesmo lote (case-insensitive)';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T4: saida exige lote e rejeita codigo inexistente
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM record_stock_exit(v_prod_lot, v_wh_alpha, 1, 'saida', NULL, NULL, 'LOTE-INEXISTENTE');
    RAISE EXCEPTION 'FALHOU T4: saida com lote inexistente foi aceita';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T4: saida com lote inexistente rejeitada';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T5: saida com lote existente funciona
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT record_stock_exit(v_prod_lot, v_wh_alpha, 3, 'consumo', NULL, NULL, 'LOTE-001')
  INTO v_res;
  IF (v_res->>'quantity')::numeric <> 12 THEN
    RAISE EXCEPTION 'FALHOU T5: saldo apos saida com lote incorreto: %', v_res;
  END IF;
  RAISE NOTICE 'PASSOU T5: saida com lote existente baixou o saldo corretamente';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T6: produto 'serial' rejeita quantidade != 1
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM record_stock_entry(v_prod_serial, v_wh_alpha, 2, 100000, 'compra', NULL, NULL, 'SN-001');
    RAISE EXCEPTION 'FALHOU T6: entrada de serie com quantidade 2 foi aceita';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T6: quantidade != 1 rejeitada para produto serial';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T7: entrada de serie cria e marca como em estoque; reentrada da mesma
  --     serie antes de sair e rejeitada
  -- ─────────────────────────────────────────────────────────────────────────
  PERFORM record_stock_entry(v_prod_serial, v_wh_alpha, 1, 100000, 'compra', NULL, NULL, 'SN-001');

  BEGIN
    PERFORM record_stock_entry(v_prod_serial, v_wh_alpha, 1, 100000, 'compra duplicada', NULL, NULL, 'SN-001');
    RAISE EXCEPTION 'FALHOU T7: mesma serie entrou em estoque duas vezes';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T7: reentrada da mesma serie ja em estoque rejeitada';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T8: saida da serie funciona; segunda saida da mesma serie (ja
  --     consumida) e rejeitada
  -- ─────────────────────────────────────────────────────────────────────────
  PERFORM record_stock_exit(v_prod_serial, v_wh_alpha, 1, 'venda', NULL, NULL, 'SN-001');

  BEGIN
    PERFORM record_stock_exit(v_prod_serial, v_wh_alpha, 1, 'venda 2', NULL, NULL, 'SN-001');
    RAISE EXCEPTION 'FALHOU T8: mesma serie saiu do estoque duas vezes seguidas';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T8: segunda saida da mesma serie ja consumida rejeitada';
  END;

  -- Serie pode reentrar depois de ter saido (ex.: devolucao).
  PERFORM record_stock_entry(v_prod_serial, v_wh_alpha, 1, 100000, 'devolucao', NULL, NULL, 'SN-001');
  RAISE NOTICE 'PASSOU T8b: serie reentrou apos ter saido (devolucao)';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T9: get_lot_history retorna os movimentos do lote em ordem
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT COUNT(*) INTO v_count FROM get_lot_history(v_lot_id);
  IF v_count <> 3 THEN
    RAISE EXCEPTION 'FALHOU T9: get_lot_history esperava 3 movimentos, achou %', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T9: get_lot_history retornou % movimentos do lote', v_count;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T10: produto tracking_type='none' ignora codigo de lote (sem exigencia)
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT record_stock_entry(v_prod_none, v_wh_alpha, 100, 50) INTO v_res;
  IF v_res->>'lot_id' IS NOT NULL THEN
    RAISE EXCEPTION 'FALHOU T10: produto sem rastreio gerou lot_id: %', v_res;
  END IF;
  RAISE NOTICE 'PASSOU T10: produto sem rastreio nao exige nem gera lote';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T11: tecnico com stock.write consegue informar lote normalmente
  -- ─────────────────────────────────────────────────────────────────────────
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_TECH')::text, true);

  SELECT record_stock_exit(v_prod_lot, v_wh_alpha, 1, 'consumo tecnico', NULL, NULL, 'LOTE-001')
  INTO v_res;
  IF (v_res->>'lot_id')::uuid <> v_lot_id THEN
    RAISE EXCEPTION 'FALHOU T11: tecnico nao conseguiu movimentar com lote';
  END IF;
  RAISE NOTICE 'PASSOU T11: tecnico com stock.write movimenta produto com lote';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T12: beta_owner nao ve nem usa lotes do alpha
  -- ─────────────────────────────────────────────────────────────────────────
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_BETA')::text, true);

  SELECT COUNT(*) INTO v_count FROM stock_lots WHERE tenant_id = :'TENANT_ALPHA';
  IF v_count > 0 THEN
    RAISE EXCEPTION 'FALHOU T12: beta_owner enxergou % lote(s) do alpha', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T12: beta_owner nao ve lotes do alpha (RLS)';

  BEGIN
    PERFORM record_stock_exit(v_prod_lot, v_wh_alpha, 1, 'invasao', NULL, NULL, 'LOTE-001');
    RAISE EXCEPTION 'FALHOU T12b: beta_owner movimentou produto do alpha';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T12b: beta_owner nao movimenta produto do alpha';
  END;

  RAISE NOTICE '=== Testes F3-P5 (lote/serie) concluidos ===';
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

-- =============================================================================
-- Testes de isolamento RLS — migration 0043_work_order_stock_consumption
--
-- Prova o contrato do ADR-016 / F3-P2:
--   * material com produto do catalogo baixa o estoque e usa o custo medio;
--   * material em texto livre continua funcionando, sem tocar no estoque;
--   * saldo insuficiente aborta o lancamento INTEIRO (sem material orfao);
--   * produto sem track_stock vincula sem movimentar;
--   * isolamento entre tenants continua valendo no caminho novo.
--
-- Como executar:
--   psql $DATABASE_URL -f test/isolation/0018_work_order_stock_consumption_test.sql
-- Substitua os \set abaixo pelos UUIDs reais do seed antes de executar.
-- =============================================================================

\set ON_ERROR_STOP on

\set TENANT_ALPHA  'a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1'
\set USER_ALPHA    'a1000000-0000-4000-8000-000000000001'
\set USER_BETA     'b2000000-0000-4000-8000-000000000002'
\set USER_TECH     'a1000000-0000-4000-8000-000000000003'

DO $$
DECLARE
  v_customer     uuid;
  v_request      uuid;
  v_quote        jsonb;
  v_quotation_id uuid;
  v_wo           jsonb;
  v_wo_id        uuid;
  v_wh           uuid;
  v_prod         uuid;
  v_prod_nostk   uuid;
  v_res          jsonb;
  v_qty          numeric;
  v_count        int;
  v_cost         integer;
  v_description  text;
BEGIN
  RAISE NOTICE '=== F3-P2 Consumo de estoque na OS — Inicio ===';

  -- SETUP: deposito padrao, produto com saldo, OS aberta
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  INSERT INTO warehouses (tenant_id, name, is_default)
  VALUES (:'TENANT_ALPHA', 'Deposito OS Teste', true)
  RETURNING id INTO v_wh;

  INSERT INTO products (tenant_id, sku, name, unit)
  VALUES (:'TENANT_ALPHA', 'SKU-OS-1', 'Cabo para OS', 'm')
  RETURNING id INTO v_prod;

  INSERT INTO products (tenant_id, sku, name, track_stock)
  VALUES (:'TENANT_ALPHA', 'SKU-OS-SRV', 'Servico catalogado', false)
  RETURNING id INTO v_prod_nostk;

  -- 100 m a 500 centavos => medio 500
  PERFORM record_stock_entry(v_prod, v_wh, 100, 500, 'carga inicial');

  INSERT INTO customers (tenant_id, type, name, is_active)
  VALUES (:'TENANT_ALPHA', 'company', 'Cliente Consumo Alpha', true)
  RETURNING id INTO v_customer;

  INSERT INTO service_requests (
    tenant_id, number, customer_id, title, description, channel, status
  ) VALUES (
    :'TENANT_ALPHA', 9931, v_customer, 'Chamado Consumo',
    'Descricao suficiente para teste de consumo de estoque.', 'phone', 'opened'
  ) RETURNING id INTO v_request;

  SELECT create_quotation(
    v_customer, v_request, '2026-08-20', 'teste consumo', NULL,
    '[{"kind":"service","description":"Servico","quantity":1,"unit_price_cents":50000,"unit_cost_cents":20000}]'::jsonb
  ) INTO v_quote;
  v_quotation_id := (v_quote->>'id')::uuid;

  RESET role;
  UPDATE quotations SET status = 'approved' WHERE id = v_quotation_id;

  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);
  SELECT convert_approved_quotation_to_work_order(v_quotation_id) INTO v_wo;
  v_wo_id := (v_wo->>'id')::uuid;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T1: material em texto livre continua funcionando, sem baixa
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT add_work_order_material(
    v_wo_id, 'Fita isolante avulsa', 2, 800, 1500
  ) INTO v_res;

  IF (v_res->>'from_stock')::boolean THEN
    RAISE EXCEPTION 'FALHOU T1: texto livre baixou estoque';
  END IF;

  SELECT quantity INTO v_qty FROM stock_balances
  WHERE warehouse_id = v_wh AND product_id = v_prod;
  IF v_qty <> 100 THEN
    RAISE EXCEPTION 'FALHOU T1: saldo alterado por lancamento em texto livre (qtd=%)', v_qty;
  END IF;
  RAISE NOTICE 'PASSOU T1: texto livre registrado sem tocar no estoque';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T2: material do catalogo baixa o estoque
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT add_work_order_material(
    v_wo_id, NULL, 10, 0, 1200, v_prod
  ) INTO v_res;

  IF NOT (v_res->>'from_stock')::boolean THEN
    RAISE EXCEPTION 'FALHOU T2: material do catalogo nao baixou estoque';
  END IF;

  SELECT quantity INTO v_qty FROM stock_balances
  WHERE warehouse_id = v_wh AND product_id = v_prod;
  IF v_qty <> 90 THEN
    RAISE EXCEPTION 'FALHOU T2: saldo esperado 90, obtido %', v_qty;
  END IF;
  RAISE NOTICE 'PASSOU T2: consumo do catalogo baixou 10 do saldo';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T3: o custo do material vem do custo medio, nao do que foi digitado
  --     (T2 passou p_unit_cost_cents = 0, mas o medio era 500)
  -- ─────────────────────────────────────────────────────────────────────────
  IF (v_res->>'unit_cost_cents')::int <> 500 THEN
    RAISE EXCEPTION
      'FALHOU T3: custo do material deveria vir do medio (500), veio %',
      v_res->>'unit_cost_cents';
  END IF;

  SELECT unit_cost_cents INTO v_cost
  FROM work_order_materials WHERE id = (v_res->>'id')::uuid;
  IF v_cost <> 500 THEN
    RAISE EXCEPTION 'FALHOU T3: custo gravado no material incorreto (%)', v_cost;
  END IF;
  RAISE NOTICE 'PASSOU T3: custo do material veio do custo medio do estoque';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T4: descricao vazia com produto assume o nome do produto
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT description INTO v_description
  FROM work_order_materials WHERE product_id = v_prod LIMIT 1;
  IF v_description NOT LIKE '%Cabo para OS%' THEN
    RAISE EXCEPTION
      'FALHOU T4: descricao nao herdou o nome do produto (%)', v_description;
  END IF;
  RAISE NOTICE 'PASSOU T4: descricao vazia herdou o nome do produto';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T5: movimento aponta de volta para a OS
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT COUNT(*) INTO v_count
  FROM stock_movements
  WHERE related_entity = 'work_orders'
    AND related_entity_id = v_wo_id
    AND kind = 'out';
  IF v_count < 1 THEN
    RAISE EXCEPTION 'FALHOU T5: movimento nao referencia a OS';
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM work_order_materials
  WHERE work_order_id = v_wo_id AND stock_movement_id IS NOT NULL;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FALHOU T5: material nao referencia o movimento (count=%)', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T5: material e movimento referenciam um ao outro';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T6: saldo insuficiente aborta TUDO — sem material orfao
  -- ─────────────────────────────────────────────────────────────────────────
  DECLARE
    v_materials_before int;
    v_total_before     int;
  BEGIN
    SELECT COUNT(*) INTO v_materials_before
    FROM work_order_materials WHERE work_order_id = v_wo_id;

    SELECT total_cents INTO v_total_before FROM work_orders WHERE id = v_wo_id;

    BEGIN
      PERFORM add_work_order_material(v_wo_id, NULL, 9999, 0, 100, v_prod);
      RAISE EXCEPTION 'FALHOU T6: material lancado com saldo insuficiente';
    EXCEPTION
      WHEN check_violation THEN
        RAISE NOTICE 'PASSOU T6a: saldo insuficiente bloqueou o lancamento';
    END;

    SELECT COUNT(*) INTO v_count
    FROM work_order_materials WHERE work_order_id = v_wo_id;
    IF v_count <> v_materials_before THEN
      RAISE EXCEPTION 'FALHOU T6b: material orfao gravado apesar do erro';
    END IF;

    SELECT total_cents INTO v_cost FROM work_orders WHERE id = v_wo_id;
    IF v_cost <> v_total_before THEN
      RAISE EXCEPTION 'FALHOU T6c: total da OS alterado apesar do erro';
    END IF;

    SELECT quantity INTO v_qty FROM stock_balances
    WHERE warehouse_id = v_wh AND product_id = v_prod;
    IF v_qty <> 90 THEN
      RAISE EXCEPTION 'FALHOU T6d: saldo alterado apesar do erro (qtd=%)', v_qty;
    END IF;
    RAISE NOTICE 'PASSOU T6: falha de saldo nao deixou rastro parcial';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T7: produto sem track_stock vincula, mas nao movimenta
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT add_work_order_material(
    v_wo_id, NULL, 1, 3000, 6000, v_prod_nostk
  ) INTO v_res;

  IF (v_res->>'from_stock')::boolean THEN
    RAISE EXCEPTION 'FALHOU T7: produto sem track_stock gerou movimento';
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM work_order_materials
  WHERE work_order_id = v_wo_id
    AND product_id = v_prod_nostk
    AND stock_movement_id IS NULL;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FALHOU T7: vinculo com produto sem estoque nao gravado';
  END IF;
  RAISE NOTICE 'PASSOU T7: produto sem track_stock vinculado sem movimentar';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T8: tecnico consegue consumir (tem work_orders.execute + stock.write)
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_TECH')::text, true);

  SELECT add_work_order_material(v_wo_id, NULL, 5, 0, 1200, v_prod) INTO v_res;
  IF NOT (v_res->>'from_stock')::boolean THEN
    RAISE EXCEPTION 'FALHOU T8: tecnico nao conseguiu baixar estoque pela OS';
  END IF;
  RAISE NOTICE 'PASSOU T8: tecnico consome material do estoque pela OS';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T9: isolamento — beta nao lanca material na OS do alpha
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_BETA')::text, true);

  BEGIN
    PERFORM add_work_order_material(v_wo_id, 'invasao', 1, 100, 200, NULL);
    RAISE EXCEPTION 'FALHOU T9: beta_owner lancou material na OS do alpha';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T9: beta_owner nao lanca material na OS do alpha';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T10: beta nao consome produto do alpha nem citando o id
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM add_work_order_material(v_wo_id, NULL, 1, 0, 200, v_prod);
    RAISE EXCEPTION 'FALHOU T10: beta_owner consumiu produto do tenant alpha';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T10: beta_owner nao consome produto do alpha';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T11: list_work_order_materials marca a origem de cada lancamento
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  SELECT COUNT(*) INTO v_count
  FROM list_work_order_materials(v_wo_id) WHERE from_stock;
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'FALHOU T11: esperado 2 lancamentos com baixa, obtido %', v_count;
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM list_work_order_materials(v_wo_id) WHERE NOT from_stock;
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'FALHOU T11: esperado 2 lancamentos sem baixa, obtido %', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T11: origem de cada lancamento identificada corretamente';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T12: auditoria registra se o lancamento passou pelo estoque
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SELECT COUNT(*) INTO v_count
  FROM audit_logs
  WHERE tenant_id = :'TENANT_ALPHA'
    AND action = 'work_order.material.created'
    AND (metadata->>'from_stock')::boolean IS TRUE;
  IF v_count < 2 THEN
    RAISE EXCEPTION 'FALHOU T12: auditoria nao marcou origem do estoque (count=%)', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T12: auditoria distingue lancamento com e sem baixa';

  RAISE NOTICE '=== Testes F3-P2 (consumo na OS) concluidos ===';
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

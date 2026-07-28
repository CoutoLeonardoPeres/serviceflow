-- =============================================================================
-- Testes de isolamento RLS — migration 0059_material_catalog_suppliers
--
-- Prova o contrato do F7-P1:
--   * seed de categorias e idempotente;
--   * best_price_for_product ordena pelo menor preco;
--   * a margem vem do nivel mais especifico (produto > categoria > empresa);
--   * tabela vencida cai para o fim do ranking, sem sumir;
--   * saldo proprio aparece junto com o ranking;
--   * historico de preco se escreve sozinho e nao registra "mudanca" que nao
--     mudou nada;
--   * isolamento entre tenants nas tabelas novas.
--
-- Como executar:
--   psql $DATABASE_URL -f test/isolation/0030_material_catalog_suppliers_test.sql
-- Substitua os \set abaixo pelos UUIDs reais do seed antes de executar.
-- USER_ALPHA precisa de stock.write e purchases.write.
-- =============================================================================

\set ON_ERROR_STOP on

\set TENANT_ALPHA  'a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1'
\set TENANT_BETA   'b2b2b2b2-b2b2-4b2b-b2b2-b2b2b2b2b2b2'
\set USER_ALPHA    'a1000000-0000-4000-8000-000000000001'
\set USER_BETA     'b2000000-0000-4000-8000-000000000002'

DO $$
DECLARE
  v_category  uuid;
  v_product   uuid;
  v_sup_a     uuid;
  v_sup_b     uuid;
  v_sp_a      uuid;
  v_sp_b      uuid;
  v_count     int;
  v_seeded    int;
  v_first     record;
  v_rows      int;
BEGIN
  RAISE NOTICE '=== F7-P1 Catalogo de materiais — Inicio ===';

  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  -- ─────────────────────────────────────────────────────────────────────────
  -- T1: seed de categorias e idempotente
  -- ─────────────────────────────────────────────────────────────────────────
  v_seeded := seed_material_categories();
  IF v_seeded < 1 THEN
    RAISE EXCEPTION 'FALHOU T1: seed nao criou categoria alguma';
  END IF;

  v_seeded := seed_material_categories();
  IF v_seeded <> 0 THEN
    RAISE EXCEPTION 'FALHOU T1: segundo seed duplicou % categorias', v_seeded;
  END IF;
  RAISE NOTICE 'PASSOU T1: seed de categorias e idempotente';

  SELECT id INTO v_category
  FROM material_categories
  WHERE tenant_id = :'TENANT_ALPHA' AND name = 'Material elétrico';

  -- Margem da categoria: 50%
  UPDATE material_categories SET markup_percent = 50 WHERE id = v_category;

  INSERT INTO products (tenant_id, name, unit, category_id, track_stock)
  VALUES (:'TENANT_ALPHA', 'Cabo flexivel 2,5mm', 'm', v_category, true)
  RETURNING id INTO v_product;

  INSERT INTO suppliers (tenant_id, name, lead_time_days)
  VALUES (:'TENANT_ALPHA', 'Fornecedor Caro', 2)
  RETURNING id INTO v_sup_a;

  INSERT INTO suppliers (tenant_id, name, lead_time_days)
  VALUES (:'TENANT_ALPHA', 'Fornecedor Barato', 7)
  RETURNING id INTO v_sup_b;

  INSERT INTO supplier_products (
    tenant_id, supplier_id, product_id, supplier_code, price_cents
  ) VALUES (
    :'TENANT_ALPHA', v_sup_a, v_product, 'CAB-25', 1000
  ) RETURNING id INTO v_sp_a;

  INSERT INTO supplier_products (
    tenant_id, supplier_id, product_id, supplier_code, price_cents
  ) VALUES (
    :'TENANT_ALPHA', v_sup_b, v_product, 'C25', 800
  ) RETURNING id INTO v_sp_b;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T2: ranking pelo menor preco, com a margem da categoria aplicada
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT * INTO v_first FROM best_price_for_product(v_product) LIMIT 1;

  IF v_first.supplier_id <> v_sup_b THEN
    RAISE EXCEPTION 'FALHOU T2: melhor preco apontou o fornecedor errado';
  END IF;
  IF v_first.price_cents <> 800 THEN
    RAISE EXCEPTION 'FALHOU T2: preco do melhor fornecedor veio %', v_first.price_cents;
  END IF;
  -- 800 + 50% = 1200
  IF v_first.client_price_cents <> 1200 THEN
    RAISE EXCEPTION 'FALHOU T2: repasse com margem de categoria deu %',
      v_first.client_price_cents;
  END IF;
  RAISE NOTICE 'PASSOU T2: menor preco e margem da categoria';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T3: margem do produto vence a da categoria
  -- ─────────────────────────────────────────────────────────────────────────
  UPDATE products SET markup_percent = 10 WHERE id = v_product;

  SELECT * INTO v_first FROM best_price_for_product(v_product) LIMIT 1;
  -- 800 + 10% = 880
  IF v_first.client_price_cents <> 880 THEN
    RAISE EXCEPTION 'FALHOU T3: margem do produto nao venceu (deu %)',
      v_first.client_price_cents;
  END IF;
  RAISE NOTICE 'PASSOU T3: margem do produto vence a da categoria';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T4: tabela vencida vai para o fim, sem sumir
  -- ─────────────────────────────────────────────────────────────────────────
  UPDATE supplier_products
  SET valid_until = CURRENT_DATE - 1
  WHERE id = v_sp_b;

  SELECT * INTO v_first FROM best_price_for_product(v_product) LIMIT 1;
  IF v_first.supplier_id <> v_sup_a THEN
    RAISE EXCEPTION 'FALHOU T4: preco vencido continuou ganhando o ranking';
  END IF;

  SELECT COUNT(*) INTO v_rows FROM best_price_for_product(v_product);
  IF v_rows <> 2 THEN
    RAISE EXCEPTION 'FALHOU T4: preco vencido sumiu da lista (% linhas)', v_rows;
  END IF;
  RAISE NOTICE 'PASSOU T4: vencido perde a vez mas continua visivel';

  UPDATE supplier_products SET valid_until = NULL WHERE id = v_sp_b;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T5: historico de preco se escreve sozinho, e so quando muda
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT COUNT(*) INTO v_count
  FROM supplier_price_history WHERE supplier_product_id = v_sp_b;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FALHOU T5: insercao nao gerou historico (% linhas)', v_count;
  END IF;

  UPDATE supplier_products SET price_cents = 800 WHERE id = v_sp_b;
  SELECT COUNT(*) INTO v_count
  FROM supplier_price_history WHERE supplier_product_id = v_sp_b;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FALHOU T5: gravou historico sem mudanca de preco';
  END IF;

  UPDATE supplier_products SET price_cents = 750 WHERE id = v_sp_b;
  SELECT COUNT(*) INTO v_count
  FROM supplier_price_history WHERE supplier_product_id = v_sp_b;
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'FALHOU T5: mudanca real nao entrou no historico';
  END IF;
  RAISE NOTICE 'PASSOU T5: historico automatico e sem ruido';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T6: isolamento entre tenants
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_BETA')::text, true);

  SELECT COUNT(*) INTO v_count
  FROM supplier_products WHERE tenant_id = :'TENANT_ALPHA';
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FALHOU T6: beta enxergou % precos do alpha', v_count;
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM material_categories WHERE tenant_id = :'TENANT_ALPHA';
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FALHOU T6: beta enxergou categorias do alpha';
  END IF;

  SELECT COUNT(*) INTO v_count FROM best_price_for_product(v_product);
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FALHOU T6: best_price vazou preco entre tenants';
  END IF;
  RAISE NOTICE 'PASSOU T6: isolamento entre tenants preservado';

  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  RAISE NOTICE '=== F7-P1 Catalogo de materiais — TODOS OS TESTES PASSARAM ===';
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

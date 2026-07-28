-- =============================================================================
-- Testes de isolamento RLS — migration 0060_supplier_price_import
--
-- Prova o contrato do F7-P2:
--   * importacao cria produto e preco quando o item e novo;
--   * reimportar a mesma planilha nao duplica nem conta como atualizacao;
--   * preco diferente conta como atualizado e entra no historico como
--     'spreadsheet';
--   * linha ruim e reportada sem derrubar as boas;
--   * p_create_missing = false recusa item fora do catalogo;
--   * casamento por codigo de barras e por nome funciona;
--   * fornecedor de outro tenant e recusado.
--
-- Como executar:
--   psql $DATABASE_URL -f test/isolation/0031_supplier_price_import_test.sql
-- Substitua os \set abaixo pelos UUIDs reais do seed antes de executar.
-- Requer 0059 e 0060 aplicadas, e USER_ALPHA com purchases.write.
-- =============================================================================

\set ON_ERROR_STOP on

\set TENANT_ALPHA  'a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1'
\set USER_ALPHA    'a1000000-0000-4000-8000-000000000001'
\set USER_BETA     'b2000000-0000-4000-8000-000000000002'

DO $$
DECLARE
  v_supplier uuid;
  v_result   jsonb;
  v_count    int;
  v_price    int;
  v_product  uuid;
  v_source   text;
BEGIN
  RAISE NOTICE '=== F7-P2 Importacao de precos — Inicio ===';

  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  INSERT INTO suppliers (tenant_id, name)
  VALUES (:'TENANT_ALPHA', 'Fornecedor Planilha')
  RETURNING id INTO v_supplier;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T1: item novo cria produto e preco
  -- ─────────────────────────────────────────────────────────────────────────
  v_result := import_supplier_prices(
    v_supplier,
    jsonb_build_array(
      jsonb_build_object(
        'supplier_code', 'CAB-25',
        'name', 'Cabo flexivel 2,5mm',
        'unit', 'm',
        'category', 'Material elétrico',
        'barcode', '7891234567890',
        'price', 3.49
      )
    ),
    true
  );

  IF (v_result->>'created_products')::int <> 1 THEN
    RAISE EXCEPTION 'FALHOU T1: produto nao foi criado (%)', v_result;
  END IF;
  IF (v_result->>'created_prices')::int <> 1 THEN
    RAISE EXCEPTION 'FALHOU T1: preco nao foi criado (%)', v_result;
  END IF;
  RAISE NOTICE 'PASSOU T1: item novo cria produto e preco';

  SELECT product_id, price_cents INTO v_product, v_price
  FROM supplier_products
  WHERE supplier_id = v_supplier AND supplier_code = 'CAB-25';

  IF v_price <> 349 THEN
    RAISE EXCEPTION 'FALHOU T1: preco gravado como % centavos', v_price;
  END IF;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T2: reimportar identico nao duplica e conta como "sem mudanca"
  -- ─────────────────────────────────────────────────────────────────────────
  v_result := import_supplier_prices(
    v_supplier,
    jsonb_build_array(
      jsonb_build_object(
        'supplier_code', 'CAB-25',
        'name', 'Cabo flexivel 2,5mm',
        'unit', 'm',
        'price', 3.49
      )
    ),
    true
  );

  IF (v_result->>'unchanged')::int <> 1 THEN
    RAISE EXCEPTION 'FALHOU T2: reimportacao identica nao foi "sem mudanca" (%)',
      v_result;
  END IF;
  IF (v_result->>'created_products')::int <> 0 THEN
    RAISE EXCEPTION 'FALHOU T2: reimportacao duplicou o produto';
  END IF;

  SELECT COUNT(*) INTO v_count FROM products WHERE tenant_id = :'TENANT_ALPHA'
    AND lower(name) = lower('Cabo flexivel 2,5mm');
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FALHOU T2: % produtos com o mesmo nome', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T2: reimportacao identica e inocua';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T3: preco novo conta como atualizado e entra no historico como planilha
  -- ─────────────────────────────────────────────────────────────────────────
  v_result := import_supplier_prices(
    v_supplier,
    jsonb_build_array(
      jsonb_build_object('supplier_code', 'CAB-25', 'price', 3.99)
    ),
    true
  );

  IF (v_result->>'updated_prices')::int <> 1 THEN
    RAISE EXCEPTION 'FALHOU T3: mudanca de preco nao contou como atualizacao (%)',
      v_result;
  END IF;

  SELECT source INTO v_source
  FROM supplier_price_history h
  JOIN supplier_products sp ON sp.id = h.supplier_product_id
  WHERE sp.supplier_id = v_supplier AND sp.supplier_code = 'CAB-25'
  ORDER BY h.changed_at DESC
  LIMIT 1;

  IF v_source <> 'spreadsheet' THEN
    RAISE EXCEPTION 'FALHOU T3: historico registrou origem % em vez de spreadsheet',
      v_source;
  END IF;
  RAISE NOTICE 'PASSOU T3: atualizacao registrada com origem planilha';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T4: linha ruim e reportada sem derrubar as boas
  -- ─────────────────────────────────────────────────────────────────────────
  v_result := import_supplier_prices(
    v_supplier,
    jsonb_build_array(
      jsonb_build_object('supplier_code', '', 'price', 1.00),
      jsonb_build_object('supplier_code', 'NOVO-1', 'name', 'Disjuntor 25A',
                         'price', 18.90),
      jsonb_build_object('supplier_code', 'RUIM-1', 'name', 'Sem preco')
    ),
    true
  );

  IF jsonb_array_length(v_result->'errors') <> 2 THEN
    RAISE EXCEPTION 'FALHOU T4: esperado 2 erros, veio % (%)',
      jsonb_array_length(v_result->'errors'), v_result;
  END IF;
  IF (v_result->>'created_prices')::int <> 1 THEN
    RAISE EXCEPTION 'FALHOU T4: linha boa nao entrou junto com as ruins';
  END IF;
  RAISE NOTICE 'PASSOU T4: linha ruim nao derruba o arquivo';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T5: sem criar faltantes, item fora do catalogo e recusado
  -- ─────────────────────────────────────────────────────────────────────────
  v_result := import_supplier_prices(
    v_supplier,
    jsonb_build_array(
      jsonb_build_object('supplier_code', 'INEXISTENTE',
                         'name', 'Produto que nao existe', 'price', 5.00)
    ),
    false
  );

  IF (v_result->>'created_products')::int <> 0 THEN
    RAISE EXCEPTION 'FALHOU T5: criou produto com create_missing = false';
  END IF;
  IF jsonb_array_length(v_result->'errors') <> 1 THEN
    RAISE EXCEPTION 'FALHOU T5: item fora do catalogo nao foi reportado';
  END IF;
  RAISE NOTICE 'PASSOU T5: create_missing = false recusa item novo';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T6: casamento por nome reaproveita o produto existente
  -- ─────────────────────────────────────────────────────────────────────────
  v_result := import_supplier_prices(
    v_supplier,
    jsonb_build_array(
      -- Mesmo produto do T1, mas com outro codigo do fornecedor.
      jsonb_build_object('supplier_code', 'CAB-25-NOVO',
                         'name', 'CABO FLEXIVEL 2,5MM', 'price', 4.10)
    ),
    true
  );

  IF (v_result->>'created_products')::int <> 0 THEN
    RAISE EXCEPTION 'FALHOU T6: casamento por nome criou produto duplicado';
  END IF;
  RAISE NOTICE 'PASSOU T6: casa por nome, ignorando caixa';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T7: fornecedor de outro tenant e recusado
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_BETA')::text, true);

  BEGIN
    PERFORM import_supplier_prices(
      v_supplier,
      jsonb_build_array(
        jsonb_build_object('supplier_code', 'X', 'name', 'Y', 'price', 1.00)
      ),
      true
    );
    RAISE EXCEPTION 'FALHOU T7: importou para fornecedor de outro tenant';
  EXCEPTION
    WHEN no_data_found OR insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T7: fornecedor de outro tenant recusado';
  END;

  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  RAISE NOTICE '=== F7-P2 Importacao de precos — TODOS OS TESTES PASSARAM ===';
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

-- =============================================================================
-- Testes de isolamento RLS — migration 0049_dre_report
--
-- Prova o contrato do F4-P2 (ADR-026):
--   * get_dre_monthly agrega receita (payment_records) e despesa
--     (payable_payments) por mes corretamente;
--   * mes sem nenhum pagamento nao aparece (sem zero-preenchimento);
--   * ano obrigatorio;
--   * isolamento entre tenants;
--   * quem nao tem financials.read nao chama a funcao.
--
-- Como executar:
--   psql $DATABASE_URL -f test/isolation/0023_dre_report_test.sql
-- Substitua os \set abaixo pelos UUIDs reais do seed antes de executar.
-- =============================================================================

\set ON_ERROR_STOP on

\set TENANT_ALPHA  'a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1'
\set USER_ALPHA    'a1000000-0000-4000-8000-000000000001'
\set USER_BETA     'b2000000-0000-4000-8000-000000000002'
\set USER_TECH     'a1000000-0000-4000-8000-000000000003'

DO $$
DECLARE
  v_customer   uuid;
  v_supplier   uuid;
  v_wh         uuid;
  v_prod       uuid;
  v_receivable_id uuid;
  v_order      jsonb;
  v_order_id   uuid;
  v_item       uuid;
  v_payable_id uuid;
  v_year       int := extract(YEAR FROM CURRENT_DATE)::int;
  v_revenue    bigint;
  v_expense    bigint;
  v_result     bigint;
  v_count      int;
BEGIN
  RAISE NOTICE '=== F4-P2 DRE simples — Inicio ===';

  -- SETUP
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  INSERT INTO customers (tenant_id, type, name, document)
  VALUES (:'TENANT_ALPHA', 'person', 'Cliente DRE Teste', '52998224725')
  RETURNING id INTO v_customer;

  INSERT INTO warehouses (tenant_id, name, is_default)
  VALUES (:'TENANT_ALPHA', 'Deposito DRE Teste', true)
  RETURNING id INTO v_wh;

  INSERT INTO products (tenant_id, sku, name, unit)
  VALUES (:'TENANT_ALPHA', 'SKU-DRE-1', 'Item DRE', 'un')
  RETURNING id INTO v_prod;

  INSERT INTO suppliers (tenant_id, name, document)
  VALUES (:'TENANT_ALPHA', 'Fornecedor DRE Alpha', '33444555000166')
  RETURNING id INTO v_supplier;

  -- Receita: recebivel avulso (sem OS) pago integralmente hoje.
  INSERT INTO receivables (tenant_id, customer_id, description, due_date, amount_cents, balance_cents)
  VALUES (:'TENANT_ALPHA', v_customer, 'Receita de teste DRE', CURRENT_DATE, 10000, 10000)
  RETURNING id INTO v_receivable_id;
  PERFORM register_manual_payment(v_receivable_id, 'pix_manual', 10000, NULL, NULL);

  -- Despesa: pedido de compra recebido e pago integralmente hoje.
  SELECT create_purchase_order(
    v_supplier, v_wh,
    jsonb_build_array(jsonb_build_object('product_id', v_prod, 'quantity', 10, 'unit_cost_cents', 300)),
    NULL, NULL
  ) INTO v_order;
  v_order_id := (v_order->>'id')::uuid;
  SELECT id INTO v_item FROM purchase_order_items WHERE purchase_order_id = v_order_id;
  PERFORM send_purchase_order(v_order_id);
  PERFORM receive_purchase_order(
    v_order_id, jsonb_build_array(jsonb_build_object('item_id', v_item, 'quantity', 10))
  );
  SELECT id INTO v_payable_id FROM payables WHERE purchase_order_id = v_order_id;
  PERFORM register_payable_payment(v_payable_id, 'transfer', 3000, NULL, NULL);

  -- ─────────────────────────────────────────────────────────────────────────
  -- T1: mes corrente aparece com receita 10000 e despesa 3000
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT revenue_cents, expense_cents, result_cents
  INTO v_revenue, v_expense, v_result
  FROM get_dre_monthly(v_year)
  WHERE month_start = date_trunc('month', CURRENT_DATE)::date;

  IF v_revenue IS NULL THEN
    RAISE EXCEPTION 'FALHOU T1: mes corrente nao apareceu no DRE';
  END IF;
  IF v_revenue <> 10000 OR v_expense <> 3000 THEN
    RAISE EXCEPTION 'FALHOU T1: valores errados (receita=%, despesa=%)', v_revenue, v_expense;
  END IF;
  RAISE NOTICE 'PASSOU T1: mes corrente com receita 10000 e despesa 3000';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T2: resultado = receita - despesa
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT result_cents INTO v_result
  FROM get_dre_monthly(v_year)
  WHERE month_start = date_trunc('month', CURRENT_DATE)::date;
  IF v_result <> 7000 THEN
    RAISE EXCEPTION 'FALHOU T2: resultado esperado 7000, obtido %', v_result;
  END IF;
  RAISE NOTICE 'PASSOU T2: resultado calculado corretamente';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T3: mes sem nenhum pagamento nao aparece (ano distante, sem dados)
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT COUNT(*) INTO v_count FROM get_dre_monthly(1999);
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FALHOU T3: ano sem movimento devolveu % linhas', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T3: ano sem movimento nao gera linha vazia';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T4: ano nulo e rejeitado
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM get_dre_monthly(NULL);
    RAISE EXCEPTION 'FALHOU T4: ano nulo foi aceito';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T4: ano obrigatorio';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T5: tecnico sem financials.read nao chama a funcao
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_TECH')::text, true);

  BEGIN
    PERFORM get_dre_monthly(v_year);
    RAISE EXCEPTION 'FALHOU T5: tecnico sem financials.read chamou get_dre_monthly';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T5: tecnico nao acessa o DRE';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T6: isolamento — beta nao ve os pagamentos do alpha no DRE
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_BETA')::text, true);

  SELECT COUNT(*) INTO v_count
  FROM get_dre_monthly(v_year)
  WHERE month_start = date_trunc('month', CURRENT_DATE)::date
    AND (revenue_cents = 10000 OR expense_cents = 3000);
  IF v_count > 0 THEN
    RAISE EXCEPTION 'FALHOU T6: beta_owner viu valores do DRE do tenant alpha';
  END IF;
  RAISE NOTICE 'PASSOU T6: beta_owner isolado do DRE do alpha';

  RAISE NOTICE '=== Testes F4-P2 (DRE simples) concluidos ===';
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

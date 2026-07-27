-- =============================================================================
-- Testes de isolamento RLS — migration 0048_payables
--
-- Prova o contrato do F4-P1 (ADR-025):
--   * receive_purchase_order gera/atualiza a payable automaticamente;
--   * recebimento parcial soma no valor da payable existente (nao duplica);
--   * baixa manual reduz o saldo e muda o status (open -> partially_paid -> paid);
--   * pagar acima do saldo e bloqueado;
--   * payable paga/cancelada nao aceita novo pagamento;
--   * payables/payable_payments nao sao graváveis direto — só via RPC;
--   * quem nao tem financials.write nao baixa pagamento;
--   * isolamento entre tenants.
--
-- Como executar:
--   psql $DATABASE_URL -f test/isolation/0022_payables_test.sql
-- Substitua os \set abaixo pelos UUIDs reais do seed antes de executar.
-- =============================================================================

\set ON_ERROR_STOP on

\set TENANT_ALPHA  'a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1'
\set USER_ALPHA    'a1000000-0000-4000-8000-000000000001'
\set USER_BETA     'b2000000-0000-4000-8000-000000000002'
\set USER_TECH     'a1000000-0000-4000-8000-000000000003'

DO $$
DECLARE
  v_supplier   uuid;
  v_wh         uuid;
  v_prod       uuid;
  v_order      jsonb;
  v_order_id   uuid;
  v_item       uuid;
  v_payable_id uuid;
  v_amount     bigint;
  v_balance    bigint;
  v_status     text;
  v_pay_res    jsonb;
  v_count      int;
BEGIN
  RAISE NOTICE '=== F4-P1 Contas a pagar — Inicio ===';

  -- SETUP
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  INSERT INTO warehouses (tenant_id, name, is_default)
  VALUES (:'TENANT_ALPHA', 'Deposito Payables Teste', true)
  RETURNING id INTO v_wh;

  INSERT INTO products (tenant_id, sku, name, unit)
  VALUES (:'TENANT_ALPHA', 'SKU-PAY-1', 'Item comprado', 'un')
  RETURNING id INTO v_prod;

  INSERT INTO suppliers (tenant_id, name, document)
  VALUES (:'TENANT_ALPHA', 'Fornecedor Payables Alpha', '22333444000155')
  RETURNING id INTO v_supplier;

  SELECT create_purchase_order(
    v_supplier, v_wh,
    jsonb_build_array(
      jsonb_build_object('product_id', v_prod, 'quantity', 100, 'unit_cost_cents', 500)
    ),
    NULL, 'pedido de teste payables'
  ) INTO v_order;
  v_order_id := (v_order->>'id')::uuid;

  SELECT id INTO v_item FROM purchase_order_items WHERE purchase_order_id = v_order_id;

  PERFORM send_purchase_order(v_order_id);

  -- ─────────────────────────────────────────────────────────────────────────
  -- T1: recebimento parcial cria a payable com o valor recebido
  --     (60 * 500 = 30000)
  -- ─────────────────────────────────────────────────────────────────────────
  PERFORM receive_purchase_order(
    v_order_id,
    jsonb_build_array(jsonb_build_object('item_id', v_item, 'quantity', 60))
  );

  SELECT id, amount_cents, balance_cents, status
  INTO v_payable_id, v_amount, v_balance, v_status
  FROM payables WHERE purchase_order_id = v_order_id;

  IF v_payable_id IS NULL THEN
    RAISE EXCEPTION 'FALHOU T1: payable nao foi criada no recebimento parcial';
  END IF;
  IF v_amount <> 30000 OR v_balance <> 30000 OR v_status <> 'open' THEN
    RAISE EXCEPTION
      'FALHOU T1: payable com valores errados (amount=%, balance=%, status=%)',
      v_amount, v_balance, v_status;
  END IF;
  RAISE NOTICE 'PASSOU T1: recebimento parcial criou payable de 30000';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T2: segundo recebimento SOMA na mesma payable, nao duplica
  --     (40 * 500 = 20000; total esperado 50000)
  -- ─────────────────────────────────────────────────────────────────────────
  PERFORM receive_purchase_order(
    v_order_id,
    jsonb_build_array(jsonb_build_object('item_id', v_item, 'quantity', 40))
  );

  SELECT COUNT(*) INTO v_count FROM payables WHERE purchase_order_id = v_order_id;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FALHOU T2: recebimento adicional duplicou a payable (count=%)', v_count;
  END IF;

  SELECT amount_cents, balance_cents INTO v_amount, v_balance
  FROM payables WHERE id = v_payable_id;
  IF v_amount <> 50000 OR v_balance <> 50000 THEN
    RAISE EXCEPTION
      'FALHOU T2: valores nao somaram corretamente (amount=%, balance=%)', v_amount, v_balance;
  END IF;
  RAISE NOTICE 'PASSOU T2: segundo recebimento somou na mesma payable (50000)';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T3: baixa parcial muda status para partially_paid
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT register_payable_payment(v_payable_id, 'transfer', 20000, 'NF-001', NULL)
  INTO v_pay_res;

  IF (v_pay_res->>'balance_cents')::bigint <> 30000 THEN
    RAISE EXCEPTION 'FALHOU T3: saldo apos baixa parcial incorreto (%)', v_pay_res->>'balance_cents';
  END IF;

  SELECT status INTO v_status FROM payables WHERE id = v_payable_id;
  IF v_status <> 'partially_paid' THEN
    RAISE EXCEPTION 'FALHOU T3b: status esperado partially_paid, obtido %', v_status;
  END IF;
  RAISE NOTICE 'PASSOU T3: baixa parcial atualizou saldo e status';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T4: pagar acima do saldo e bloqueado
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM register_payable_payment(v_payable_id, 'transfer', 999999, NULL, NULL);
    RAISE EXCEPTION 'FALHOU T4: pagamento acima do saldo foi aceito';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T4: pagamento acima do saldo bloqueado';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T5: baixa do restante fecha como paid
  -- ─────────────────────────────────────────────────────────────────────────
  PERFORM register_payable_payment(v_payable_id, 'pix_manual', 30000, NULL, NULL);

  SELECT status, balance_cents INTO v_status, v_balance FROM payables WHERE id = v_payable_id;
  IF v_status <> 'paid' OR v_balance <> 0 THEN
    RAISE EXCEPTION 'FALHOU T5: payable nao fechou como paga (status=%, saldo=%)', v_status, v_balance;
  END IF;
  RAISE NOTICE 'PASSOU T5: payable quitada';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T6: payable paga nao aceita novo pagamento
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM register_payable_payment(v_payable_id, 'cash', 100, NULL, NULL);
    RAISE EXCEPTION 'FALHOU T6: payable paga aceitou novo pagamento';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T6: payable paga rejeita novo pagamento';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T7: payables/payable_payments nao sao graváveis direto
  -- ─────────────────────────────────────────────────────────────────────────
  UPDATE payables SET status = 'open' WHERE id = v_payable_id;
  IF FOUND THEN
    RAISE EXCEPTION 'FALHOU T7: payable alterada sem passar por RPC';
  END IF;

  BEGIN
    INSERT INTO payable_payments (tenant_id, payable_id, method, amount_cents)
    VALUES (:'TENANT_ALPHA', v_payable_id, 'cash', 100);
    RAISE EXCEPTION 'FALHOU T7b: payable_payments aceitou insercao direta';
  EXCEPTION
    WHEN insufficient_privilege OR undefined_object THEN
      RAISE NOTICE 'PASSOU T7b: payable_payments nao aceita insercao direta';
  END;
  RAISE NOTICE 'PASSOU T7: payables/payable_payments so mudam via RPC';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T8: list_payables devolve a payable com dados do fornecedor/pedido
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT COUNT(*) INTO v_count
  FROM list_payables('paid')
  WHERE id = v_payable_id AND supplier_id = v_supplier;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FALHOU T8: list_payables nao devolveu a payable esperada';
  END IF;
  RAISE NOTICE 'PASSOU T8: list_payables consistente';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T9: tecnico (sem financials.write) nao baixa pagamento
  -- ─────────────────────────────────────────────────────────────────────────
  -- Nova payable para testar, ja que a anterior esta paga.
  DECLARE
    v_order2 jsonb;
    v_order2_id uuid;
    v_item2 uuid;
    v_payable2 uuid;
  BEGIN
    SELECT create_purchase_order(
      v_supplier, v_wh,
      jsonb_build_array(
        jsonb_build_object('product_id', v_prod, 'quantity', 5, 'unit_cost_cents', 1000)
      ),
      NULL, NULL
    ) INTO v_order2;
    v_order2_id := (v_order2->>'id')::uuid;
    SELECT id INTO v_item2 FROM purchase_order_items WHERE purchase_order_id = v_order2_id;
    PERFORM send_purchase_order(v_order2_id);
    PERFORM receive_purchase_order(
      v_order2_id, jsonb_build_array(jsonb_build_object('item_id', v_item2, 'quantity', 5))
    );
    SELECT id INTO v_payable2 FROM payables WHERE purchase_order_id = v_order2_id;

    RESET role;
    SET LOCAL role = authenticated;
    PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_TECH')::text, true);

    BEGIN
      PERFORM register_payable_payment(v_payable2, 'cash', 100, NULL, NULL);
      RAISE EXCEPTION 'FALHOU T9: tecnico sem financials.write baixou pagamento';
    EXCEPTION
      WHEN insufficient_privilege THEN
        RAISE NOTICE 'PASSOU T9: tecnico nao baixa pagamento de payable';
    END;
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T10: isolamento — beta nao ve payable do alpha
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_BETA')::text, true);

  SELECT COUNT(*) INTO v_count FROM payables WHERE id = v_payable_id;
  IF v_count > 0 THEN
    RAISE EXCEPTION 'FALHOU T10: beta_owner viu payable do tenant alpha';
  END IF;

  BEGIN
    PERFORM register_payable_payment(v_payable_id, 'cash', 100, NULL, NULL);
    RAISE EXCEPTION 'FALHOU T10b: beta_owner baixou pagamento de payable do alpha';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T10b: beta_owner nao baixa payable do alpha';
  END;
  RAISE NOTICE 'PASSOU T10: beta_owner isolado das payables do alpha';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T11: auditoria da baixa de pagamento
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SELECT COUNT(*) INTO v_count
  FROM audit_logs
  WHERE tenant_id = :'TENANT_ALPHA'
    AND action = 'financial.payable_payment.registered';
  IF v_count < 2 THEN
    RAISE EXCEPTION 'FALHOU T11: baixas de payable nao auditadas (count=%)', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T11: % baixa(s) de payable auditada(s)', v_count;

  RAISE NOTICE '=== Testes F4-P1 (contas a pagar) concluidos ===';
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

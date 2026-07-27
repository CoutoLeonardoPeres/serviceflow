-- =============================================================================
-- Testes de isolamento RLS — migration 0013_financials_minimum
--
-- Reescrito em 2026-07-24: a versão anterior era um roteiro manual sem
-- asserções automáticas nem verificação de isolamento entre tenants.
--
-- Como executar:
--   psql $DATABASE_URL -f test/isolation/0012_financials_minimum_test.sql
-- Substitua os \set abaixo pelos UUIDs reais do seed antes de executar.
-- =============================================================================

\set ON_ERROR_STOP on

\set TENANT_ALPHA  'a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1'
\set USER_ALPHA    'a1000000-0000-4000-8000-000000000001'
\set USER_BETA     'b2000000-0000-4000-8000-000000000002'

DO $$
DECLARE
  v_customer_alpha uuid;
  v_request_alpha  uuid;
  v_quote          jsonb;
  v_quotation_id   uuid;
  v_wo             jsonb;
  v_wo_id          uuid;
  v_receivable     jsonb;
  v_receivable_id  uuid;
  v_payment        jsonb;
  v_status         text;
  v_balance        int;
  v_count          int;
BEGIN
  RAISE NOTICE '=== E8 RLS Financials — Inicio ===';

  -- SETUP: cliente, chamado, orcamento aprovado, OS convertida e concluida
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);
  INSERT INTO customers (tenant_id, type, name, is_active)
  VALUES (:'TENANT_ALPHA', 'company', 'Cliente Financeiro Alpha', true)
  RETURNING id INTO v_customer_alpha;

  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);
  INSERT INTO service_requests (
    tenant_id, number, customer_id, title, description, channel, status
  ) VALUES (
    :'TENANT_ALPHA', 9801, v_customer_alpha, 'Chamado Financeiro Alpha',
    'Descricao suficiente para teste financeiro alpha.', 'phone', 'opened'
  ) RETURNING id INTO v_request_alpha;

  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  SELECT create_quotation(
    v_customer_alpha, v_request_alpha, '2026-08-20', 'teste', NULL,
    '[{"kind":"service","description":"Servico","quantity":1,"unit_price_cents":100000,"unit_cost_cents":40000}]'::jsonb
  ) INTO v_quote;
  v_quotation_id := (v_quote->>'id')::uuid;

  RESET role;
  UPDATE quotations SET status = 'approved' WHERE id = v_quotation_id;

  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);
  SELECT convert_approved_quotation_to_work_order(v_quotation_id) INTO v_wo;
  v_wo_id := (v_wo->>'id')::uuid;
  PERFORM transition_work_order(v_wo_id, 'done', 'concluida para faturamento');

  -- ─────────────────────────────────────────────────────────────────────────
  -- T1: recebivel criado a partir da OS com valor da OS
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT create_receivable_from_work_order(v_wo_id, CURRENT_DATE) INTO v_receivable;
  v_receivable_id := (v_receivable->>'id')::uuid;

  IF (v_receivable->>'amount_cents')::int <> 100000 THEN
    RAISE EXCEPTION 'FALHOU T1: valor do recebivel incorreto (%)', v_receivable->>'amount_cents';
  END IF;
  RAISE NOTICE 'PASSOU T1: recebivel criado com valor correto (id=%)', v_receivable_id;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T2: criacao do recebivel e idempotente (mesma OS nao duplica)
  -- ─────────────────────────────────────────────────────────────────────────
  PERFORM create_receivable_from_work_order(v_wo_id, CURRENT_DATE);

  SELECT COUNT(*) INTO v_count FROM receivables WHERE work_order_id = v_wo_id;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FALHOU T2: recebivel duplicado para a mesma OS (count=%)', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T2: criacao de recebivel e idempotente';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T3: pagamento parcial — status vira partially_paid
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT register_manual_payment(v_receivable_id, 'pix_manual', 40000, 'PIX-TESTE-1', 'Pagamento parcial')
  INTO v_payment;

  SELECT status, balance_cents INTO v_status, v_balance FROM receivables WHERE id = v_receivable_id;
  IF v_status <> 'partially_paid' OR v_balance <> 60000 THEN
    RAISE EXCEPTION 'FALHOU T3: status/saldo incorretos apos pagamento parcial (status=%, saldo=%)', v_status, v_balance;
  END IF;
  RAISE NOTICE 'PASSOU T3: pagamento parcial registrado (saldo restante=%)', v_balance;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T4: pagamento do saldo restante — status vira paid e recibo e gerado
  -- ─────────────────────────────────────────────────────────────────────────
  PERFORM register_manual_payment(v_receivable_id, 'cash', 60000, NULL, 'Quitacao');

  SELECT status, balance_cents INTO v_status, v_balance FROM receivables WHERE id = v_receivable_id;
  IF v_status <> 'paid' OR v_balance <> 0 THEN
    RAISE EXCEPTION 'FALHOU T4: recebivel nao foi quitado corretamente (status=%, saldo=%)', v_status, v_balance;
  END IF;

  SELECT COUNT(*) INTO v_count FROM receipts WHERE receivable_id = v_receivable_id;
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'FALHOU T4: quantidade de recibos inesperada (esperado 2 pagamentos, count=%)', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T4: recebivel quitado e % recibo(s) gerado(s)', v_count;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T5: pagamento acima do saldo disponivel e bloqueado
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM register_manual_payment(v_receivable_id, 'cash', 1000, NULL, 'excedente');
    RAISE EXCEPTION 'FALHOU T5: pagamento acima do saldo foi aceito';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T5: pagamento acima do saldo foi bloqueado';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T6: isolamento — beta nao ve nem paga recebivel do alpha
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_BETA')::text, true);

  SELECT COUNT(*) INTO v_count FROM receivables WHERE id = v_receivable_id;
  IF v_count > 0 THEN
    RAISE EXCEPTION 'FALHOU T6: beta_owner viu recebivel do tenant alpha';
  END IF;
  RAISE NOTICE 'PASSOU T6: beta_owner nao ve recebivel do tenant alpha';

  BEGIN
    PERFORM register_manual_payment(v_receivable_id, 'cash', 100, NULL, 'tentativa cross tenant');
    RAISE EXCEPTION 'FALHOU T7: beta_owner registrou pagamento em recebivel do tenant alpha';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T7: beta_owner nao registra pagamento em recebivel do tenant alpha';
  END;

  RAISE NOTICE '=== Testes E8 (financeiro) concluidos ===';
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

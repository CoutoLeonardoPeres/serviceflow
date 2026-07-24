-- =============================================================================
-- Testes de isolamento RLS — migration 0011_work_order_expenses
--
-- Reescrito em 2026-07-24: a versão anterior era um roteiro manual comentado,
-- sem asserções automáticas nem verificação de isolamento entre tenants.
--
-- Como executar:
--   psql $DATABASE_URL -f test/isolation/0010_work_order_expenses_test.sql
-- Substitua os \set abaixo pelos UUIDs reais do seed antes de executar.
-- =============================================================================

\set ON_ERROR_STOP on

\set TENANT_ALPHA  'a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1'
\set USER_ALPHA    'a1000000-0000-4000-8000-000000000001'
\set USER_BETA     'b2000000-0000-4000-8000-000000000002'
\set USER_TECH     'a1000000-0000-4000-8000-000000000003'

DO $$
DECLARE
  v_customer_alpha uuid;
  v_request_alpha  uuid;
  v_quote          jsonb;
  v_quotation_id   uuid;
  v_wo             jsonb;
  v_wo_id          uuid;
  v_expense        jsonb;
  v_count          int;
BEGIN
  RAISE NOTICE '=== E7 RLS Work Order Expenses — Inicio ===';

  -- SETUP: cliente, chamado, orcamento aprovado, OS convertida
  INSERT INTO customers (tenant_id, type, name, is_active)
  VALUES (:'TENANT_ALPHA', 'company', 'Cliente Despesas Alpha', true)
  RETURNING id INTO v_customer_alpha;

  INSERT INTO service_requests (
    tenant_id, number, customer_id, title, description, channel, status
  ) VALUES (
    :'TENANT_ALPHA', 9601, v_customer_alpha, 'Chamado Despesas Alpha',
    'Descricao suficiente para teste de despesas alpha.', 'phone', 'opened'
  ) RETURNING id INTO v_request_alpha;

  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  SELECT create_quotation(
    v_customer_alpha, v_request_alpha, '2026-08-20', 'teste', NULL,
    '[{"kind":"service","description":"Visita","quantity":1,"unit_price_cents":20000,"unit_cost_cents":8000}]'::jsonb
  ) INTO v_quote;
  v_quotation_id := (v_quote->>'id')::uuid;

  RESET role;
  UPDATE quotations SET status = 'approved' WHERE id = v_quotation_id;

  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);
  SELECT convert_approved_quotation_to_work_order(v_quotation_id) INTO v_wo;
  v_wo_id := (v_wo->>'id')::uuid;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T1: despesa valida registrada
  -- ─────────────────────────────────────────────────────────────────────────
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_TECH')::text, true);

  SELECT add_work_order_expense(v_wo_id, 'parking', 2500, 'Estacionamento durante atendimento.')
  INTO v_expense;

  SELECT COUNT(*) INTO v_count FROM work_order_expenses WHERE work_order_id = v_wo_id;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FALHOU T1: despesa nao foi registrada (count=%)', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T1: despesa registrada (id=%)', v_expense->>'id';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T2: tipo de despesa invalido e bloqueado
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM add_work_order_expense(v_wo_id, 'invalid_kind', 1000, 'tipo invalido');
    RAISE EXCEPTION 'FALHOU T2: tipo de despesa invalido foi aceito';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T2: tipo de despesa invalido foi bloqueado';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T3: valor de despesa invalido (<=0) e bloqueado
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM add_work_order_expense(v_wo_id, 'meal', 0, 'valor invalido');
    RAISE EXCEPTION 'FALHOU T3: despesa com valor zero foi aceita';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T3: despesa com valor zero foi bloqueada';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T4: OS finalizada nao aceita nova despesa
  -- ─────────────────────────────────────────────────────────────────────────
  PERFORM transition_work_order(v_wo_id, 'done', 'concluida para teste');

  BEGIN
    PERFORM add_work_order_expense(v_wo_id, 'toll', 500, 'apos conclusao');
    RAISE EXCEPTION 'FALHOU T4: despesa em OS finalizada foi aceita';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T4: despesa em OS finalizada foi bloqueada';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T5: isolamento — beta nao registra despesa na OS do alpha
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_BETA')::text, true);

  BEGIN
    PERFORM add_work_order_expense(v_wo_id, 'other', 100, 'tentativa cross tenant');
    RAISE EXCEPTION 'FALHOU T5: beta_owner registrou despesa na OS do tenant alpha';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T5: beta_owner nao registra despesa na OS do tenant alpha';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T6: auditoria — despesa gerou evento
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SELECT COUNT(*) INTO v_count
  FROM audit_logs
  WHERE action = 'work_order.expense.created'
    AND tenant_id = :'TENANT_ALPHA';

  IF v_count < 1 THEN
    RAISE EXCEPTION 'FALHOU T6: despesa nao gerou audit_log (count=%)', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T6: % evento(s) de auditoria de despesa registrado(s)', v_count;

  RAISE NOTICE '=== Testes E7 (despesas) concluidos ===';
  RAISE EXCEPTION 'ROLLBACK_TEST_DATA' USING DETAIL = 'Dados de teste removidos.';

EXCEPTION
  WHEN SQLSTATE 'P0001' AND SQLERRM = 'ROLLBACK_TEST_DATA' THEN
    RAISE NOTICE 'Dados de teste revertidos (rollback intencional).';
END;
$$;

-- =============================================================================
-- Testes de isolamento RLS — migration 0008_work_orders
-- (Nome do arquivo mantido como 0007 por compatibilidade com PROJECT_STATE.md)
--
-- Reescrito em 2026-07-24: a versão anterior era um roteiro manual comentado,
-- sem asserções automáticas nem verificação de isolamento entre tenants.
-- Esta versão segue o mesmo padrão automatizado de 0002-0006_*.sql.
--
-- Como executar:
--   psql $DATABASE_URL -f test/isolation/0007_work_orders_test.sql
-- Substitua os \set abaixo pelos UUIDs reais do seed antes de executar.
-- =============================================================================

\set ON_ERROR_STOP on

\set TENANT_ALPHA  'a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1'
\set TENANT_BETA   'b2b2b2b2-b2b2-4b2b-b2b2-b2b2b2b2b2b2'
\set USER_ALPHA    'a1000000-0000-4000-8000-000000000001'
\set USER_BETA     'b2000000-0000-4000-8000-000000000002'

DO $$
DECLARE
  v_customer_alpha uuid;
  v_request_alpha  uuid;
  v_quote          jsonb;
  v_quotation_id   uuid;
  v_wo_first       jsonb;
  v_wo_second      jsonb;
  v_wo_id          uuid;
  v_count          int;
BEGIN
  RAISE NOTICE '=== E7 RLS Work Orders — Inicio ===';

  -- ─────────────────────────────────────────────────────────────────────────
  -- SETUP (sem RLS: superuser/service role): cliente, chamado, orcamento
  -- ─────────────────────────────────────────────────────────────────────────
  INSERT INTO customers (tenant_id, type, name, is_active)
  VALUES (:'TENANT_ALPHA', 'company', 'Cliente OS Alpha', true)
  RETURNING id INTO v_customer_alpha;

  INSERT INTO service_requests (
    tenant_id, number, customer_id, title, description, channel, status
  ) VALUES (
    :'TENANT_ALPHA', 9301, v_customer_alpha, 'Chamado OS Alpha',
    'Descricao suficiente para teste de OS alpha.', 'phone', 'opened'
  ) RETURNING id INTO v_request_alpha;

  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  SELECT create_quotation(
    v_customer_alpha, v_request_alpha, '2026-08-20', 'teste', NULL,
    '[{"kind":"service","description":"Instalacao","quantity":1,"unit_price_cents":50000,"unit_cost_cents":20000}]'::jsonb
  ) INTO v_quote;
  v_quotation_id := (v_quote->>'id')::uuid;

  -- Aprovacao direta (equivalente ao fluxo publico decide_public_quotation)
  RESET role;
  UPDATE quotations SET status = 'approved' WHERE id = v_quotation_id;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T1: conversao bloqueada para orcamento nao aprovado
  -- ─────────────────────────────────────────────────────────────────────────
  UPDATE quotations SET status = 'draft' WHERE id = v_quotation_id;

  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  BEGIN
    PERFORM convert_approved_quotation_to_work_order(v_quotation_id);
    RAISE EXCEPTION 'FALHOU T1: orcamento nao aprovado foi convertido em OS';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T1: conversao de orcamento nao aprovado foi bloqueada';
  END;

  RESET role;
  UPDATE quotations SET status = 'approved' WHERE id = v_quotation_id;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T2: conversao idempotente — duas chamadas retornam a mesma OS
  -- ─────────────────────────────────────────────────────────────────────────
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  SELECT convert_approved_quotation_to_work_order(v_quotation_id) INTO v_wo_first;
  SELECT convert_approved_quotation_to_work_order(v_quotation_id) INTO v_wo_second;

  IF (v_wo_first->>'id') IS DISTINCT FROM (v_wo_second->>'id') THEN
    RAISE EXCEPTION 'FALHOU T2: conversao nao foi idempotente (% <> %)',
      v_wo_first->>'id', v_wo_second->>'id';
  END IF;
  v_wo_id := (v_wo_first->>'id')::uuid;
  RAISE NOTICE 'PASSOU T2: conversao idempotente — OS unica (id=%)', v_wo_id;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T3: itens da OS foram espelhados do orcamento
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT COUNT(*) INTO v_count FROM work_order_items WHERE work_order_id = v_wo_id;
  IF v_count < 1 THEN
    RAISE EXCEPTION 'FALHOU T3: OS criada sem itens espelhados (count=%)', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T3: % item(ns) espelhado(s) do orcamento na OS', v_count;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T4: isolamento — beta nao ve a OS do alpha
  -- ─────────────────────────────────────────────────────────────────────────
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_BETA')::text, true);

  SELECT COUNT(*) INTO v_count FROM work_orders WHERE id = v_wo_id;
  IF v_count > 0 THEN
    RAISE EXCEPTION 'FALHOU T4: beta_owner viu a OS do tenant alpha';
  END IF;
  RAISE NOTICE 'PASSOU T4: beta_owner nao ve a OS do tenant alpha';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T5: isolamento — beta nao converte orcamento do alpha (nao encontrado)
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM convert_approved_quotation_to_work_order(v_quotation_id);
    RAISE EXCEPTION 'FALHOU T5: beta_owner converteu orcamento do tenant alpha';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T5: beta_owner nao converte orcamento do tenant alpha';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T6: transicao de status — OS finalizada nao muda mais de status
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  PERFORM transition_work_order(v_wo_id, 'in_progress', 'iniciando execucao');
  PERFORM transition_work_order(v_wo_id, 'done', 'concluida');

  BEGIN
    PERFORM transition_work_order(v_wo_id, 'in_progress', 'tentativa invalida');
    RAISE EXCEPTION 'FALHOU T6: OS finalizada aceitou nova transicao de status';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T6: OS finalizada bloqueou nova transicao de status';
  END;

  RAISE NOTICE '=== Testes E7 (work orders) concluidos ===';
  RAISE EXCEPTION 'ROLLBACK_TEST_DATA' USING DETAIL = 'Dados de teste removidos.';

EXCEPTION
  WHEN SQLSTATE 'P0001' AND SQLERRM = 'ROLLBACK_TEST_DATA' THEN
    RAISE NOTICE 'Dados de teste revertidos (rollback intencional).';
END;
$$;

-- =============================================================================
-- Testes de isolamento RLS — migration 0014_customer_satisfaction
--
-- Reescrito em 2026-07-24: a versão anterior era um roteiro manual comentado,
-- sem asserções automáticas nem verificação de isolamento entre tenants.
--
-- Como executar:
--   psql $DATABASE_URL -f test/isolation/0013_customer_satisfaction_test.sql
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
  v_satisfaction   jsonb;
  v_rating         int;
  v_count          int;
BEGIN
  RAISE NOTICE '=== F2 RLS Customer Satisfaction — Inicio ===';

  -- SETUP: cliente, chamado, orcamento aprovado, OS convertida (ainda aberta)
  INSERT INTO customers (tenant_id, type, name, is_active)
  VALUES (:'TENANT_ALPHA', 'company', 'Cliente Satisfacao Alpha', true)
  RETURNING id INTO v_customer_alpha;

  INSERT INTO service_requests (
    tenant_id, number, customer_id, title, description, channel, status
  ) VALUES (
    :'TENANT_ALPHA', 9901, v_customer_alpha, 'Chamado Satisfacao Alpha',
    'Descricao suficiente para teste de satisfacao alpha.', 'phone', 'opened'
  ) RETURNING id INTO v_request_alpha;

  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  SELECT create_quotation(
    v_customer_alpha, v_request_alpha, '2026-08-20', 'teste', NULL,
    '[{"kind":"service","description":"Manutencao","quantity":1,"unit_price_cents":35000,"unit_cost_cents":15000}]'::jsonb
  ) INTO v_quote;
  v_quotation_id := (v_quote->>'id')::uuid;

  RESET role;
  UPDATE quotations SET status = 'approved' WHERE id = v_quotation_id;

  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);
  SELECT convert_approved_quotation_to_work_order(v_quotation_id) INTO v_wo;
  v_wo_id := (v_wo->>'id')::uuid;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T1: OS ainda nao concluida (opened) bloqueia registro de satisfacao
  -- ─────────────────────────────────────────────────────────────────────────
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_TECH')::text, true);

  BEGIN
    PERFORM record_work_order_satisfaction(v_wo_id, 5, 'Cliente Teste', 'Ainda nao deveria funcionar.');
    RAISE EXCEPTION 'FALHOU T1: satisfacao registrada em OS nao concluida';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T1: satisfacao bloqueada em OS nao concluida';
  END;

  -- Concluir a OS
  PERFORM transition_work_order(v_wo_id, 'done', 'concluida para teste de satisfacao');

  -- ─────────────────────────────────────────────────────────────────────────
  -- T2: nota fora do intervalo 1-5 e bloqueada
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM record_work_order_satisfaction(v_wo_id, 6, 'Cliente Teste', 'Nota invalida.');
    RAISE EXCEPTION 'FALHOU T2: nota fora do intervalo foi aceita';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T2: nota fora do intervalo foi bloqueada';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T3: satisfacao registrada com sucesso apos conclusao
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT record_work_order_satisfaction(v_wo_id, 5, 'Cliente Teste', 'Atendimento excelente.')
  INTO v_satisfaction;

  IF (v_satisfaction->>'rating')::int <> 5 THEN
    RAISE EXCEPTION 'FALHOU T3: nota registrada incorretamente (%)', v_satisfaction->>'rating';
  END IF;
  RAISE NOTICE 'PASSOU T3: satisfacao registrada (id=%)', v_satisfaction->>'id';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T4: upsert — segunda chamada atualiza a avaliacao existente (nao duplica)
  -- ─────────────────────────────────────────────────────────────────────────
  PERFORM record_work_order_satisfaction(v_wo_id, 3, 'Cliente Teste', 'Revisando a nota.');

  SELECT COUNT(*) INTO v_count FROM work_order_satisfaction WHERE work_order_id = v_wo_id;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FALHOU T4: avaliacao duplicada em vez de atualizada (count=%)', v_count;
  END IF;

  SELECT rating INTO v_rating FROM work_order_satisfaction WHERE work_order_id = v_wo_id;
  IF v_rating <> 3 THEN
    RAISE EXCEPTION 'FALHOU T4: avaliacao nao foi atualizada (rating=%)', v_rating;
  END IF;
  RAISE NOTICE 'PASSOU T4: segunda chamada atualizou a avaliacao existente (upsert)';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T5: isolamento — beta nao ve nem registra satisfacao na OS do alpha
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_BETA')::text, true);

  SELECT COUNT(*) INTO v_count FROM work_order_satisfaction WHERE work_order_id = v_wo_id;
  IF v_count > 0 THEN
    RAISE EXCEPTION 'FALHOU T5: beta_owner viu satisfacao da OS do tenant alpha';
  END IF;
  RAISE NOTICE 'PASSOU T5: beta_owner nao ve satisfacao da OS do tenant alpha';

  BEGIN
    PERFORM record_work_order_satisfaction(v_wo_id, 1, 'Invasor', 'tentativa cross tenant');
    RAISE EXCEPTION 'FALHOU T6: beta_owner registrou satisfacao na OS do tenant alpha';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T6: beta_owner nao registra satisfacao na OS do tenant alpha';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T7: auditoria — satisfacao gerou evento
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SELECT COUNT(*) INTO v_count
  FROM audit_logs
  WHERE action = 'work_order.satisfaction.recorded'
    AND tenant_id = :'TENANT_ALPHA';

  IF v_count < 1 THEN
    RAISE EXCEPTION 'FALHOU T7: satisfacao nao gerou audit_log (count=%)', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T7: % evento(s) de auditoria de satisfacao registrado(s)', v_count;

  RAISE NOTICE '=== Testes F2 (satisfacao) concluidos ===';
  RAISE EXCEPTION 'ROLLBACK_TEST_DATA' USING DETAIL = 'Dados de teste removidos.';

EXCEPTION
  WHEN SQLSTATE 'P0001' AND SQLERRM = 'ROLLBACK_TEST_DATA' THEN
    RAISE NOTICE 'Dados de teste revertidos (rollback intencional).';
END;
$$;

-- =============================================================================
-- Testes de isolamento RLS — migration 0010_work_order_acceptance
--
-- Reescrito em 2026-07-24: a versão anterior era um roteiro manual comentado,
-- sem asserções automáticas nem verificação de isolamento entre tenants.
--
-- Como executar:
--   psql $DATABASE_URL -f test/isolation/0009_work_order_acceptance_test.sql
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
  v_acceptance     jsonb;
  v_status         text;
  v_count          int;
  v_signer         text;
BEGIN
  RAISE NOTICE '=== E7 RLS Work Order Acceptance — Inicio ===';

  -- SETUP: cliente, chamado, orcamento aprovado, OS convertida
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);
  INSERT INTO customers (tenant_id, type, name, is_active)
  VALUES (:'TENANT_ALPHA', 'company', 'Cliente Aceite Alpha', true)
  RETURNING id INTO v_customer_alpha;

  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);
  INSERT INTO service_requests (
    tenant_id, number, customer_id, title, description, channel, status
  ) VALUES (
    :'TENANT_ALPHA', 9501, v_customer_alpha, 'Chamado Aceite Alpha',
    'Descricao suficiente para teste de aceite alpha.', 'phone', 'opened'
  ) RETURNING id INTO v_request_alpha;

  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  SELECT create_quotation(
    v_customer_alpha, v_request_alpha, '2026-08-20', 'teste', NULL,
    '[{"kind":"service","description":"Reparo","quantity":1,"unit_price_cents":30000,"unit_cost_cents":10000}]'::jsonb
  ) INTO v_quote;
  v_quotation_id := (v_quote->>'id')::uuid;

  RESET role;
  UPDATE quotations SET status = 'approved' WHERE id = v_quotation_id;

  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);
  SELECT convert_approved_quotation_to_work_order(v_quotation_id) INTO v_wo;
  v_wo_id := (v_wo->>'id')::uuid;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T1: nome do responsavel invalido (menos de 2 caracteres) e bloqueado
  -- ─────────────────────────────────────────────────────────────────────────
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_TECH')::text, true);

  BEGIN
    PERFORM record_work_order_acceptance(v_wo_id, 'A', NULL, NULL);
    RAISE EXCEPTION 'FALHOU T1: nome de responsavel invalido foi aceito';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T1: nome de responsavel invalido foi bloqueado';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T2: aceite registrado — OS vira 'done'
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT record_work_order_acceptance(
    v_wo_id, 'Maria Cliente', '***.123.456-**', 'Servico conferido no local.'
  ) INTO v_acceptance;

  SELECT status INTO v_status FROM work_orders WHERE id = v_wo_id;
  IF v_status <> 'done' THEN
    RAISE EXCEPTION 'FALHOU T2: OS nao transicionou para done apos aceite (status=%)', v_status;
  END IF;
  RAISE NOTICE 'PASSOU T2: aceite registrado e OS concluida (id=%)', v_acceptance->>'id';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T3: upsert — segundo aceite atualiza o mesmo registro (nao duplica)
  -- ─────────────────────────────────────────────────────────────────────────
  PERFORM record_work_order_acceptance(
    v_wo_id, 'Maria Cliente Correta', '***.123.456-**', 'Correcao do nome.'
  );

  SELECT COUNT(*) INTO v_count FROM work_order_acceptances WHERE work_order_id = v_wo_id;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FALHOU T3: aceite duplicado em vez de atualizado (count=%)', v_count;
  END IF;

  SELECT signer_name INTO v_signer FROM work_order_acceptances WHERE work_order_id = v_wo_id;
  IF v_signer <> 'Maria Cliente Correta' THEN
    RAISE EXCEPTION 'FALHOU T3: aceite nao foi atualizado (signer_name=%)', v_signer;
  END IF;
  RAISE NOTICE 'PASSOU T3: segundo aceite atualizou o registro existente (upsert)';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T4: isolamento — beta nao registra aceite na OS do alpha
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_BETA')::text, true);

  BEGIN
    PERFORM record_work_order_acceptance(v_wo_id, 'Invasor Beta', NULL, NULL);
    RAISE EXCEPTION 'FALHOU T4: beta_owner registrou aceite na OS do tenant alpha';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T4: beta_owner nao registra aceite na OS do tenant alpha';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T5: auditoria — aceite gerou evento
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SELECT COUNT(*) INTO v_count
  FROM audit_logs
  WHERE action = 'work_order.acceptance.recorded'
    AND tenant_id = :'TENANT_ALPHA';

  IF v_count < 1 THEN
    RAISE EXCEPTION 'FALHOU T5: aceite nao gerou audit_log (count=%)', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T5: % evento(s) de auditoria de aceite registrado(s)', v_count;

  RAISE NOTICE '=== Testes E7 (aceite) concluidos ===';
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

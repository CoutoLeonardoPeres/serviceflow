-- =============================================================================
-- Testes de isolamento RLS — migration 0012_work_order_evidence_storage
--
-- Reescrito em 2026-07-24: a versão anterior era um roteiro manual sem
-- asserções automáticas nem verificação de isolamento entre tenants.
--
-- Como executar:
--   psql $DATABASE_URL -f test/isolation/0011_work_order_evidence_storage_test.sql
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
  v_evidence       jsonb;
  v_path_ok        text;
  v_count          int;
BEGIN
  RAISE NOTICE '=== E7 RLS Work Order Evidence — Inicio ===';

  -- SETUP: cliente, chamado, orcamento aprovado, OS convertida
  INSERT INTO customers (tenant_id, type, name, is_active)
  VALUES (:'TENANT_ALPHA', 'company', 'Cliente Evidencia Alpha', true)
  RETURNING id INTO v_customer_alpha;

  INSERT INTO service_requests (
    tenant_id, number, customer_id, title, description, channel, status
  ) VALUES (
    :'TENANT_ALPHA', 9701, v_customer_alpha, 'Chamado Evidencia Alpha',
    'Descricao suficiente para teste de evidencia alpha.', 'phone', 'opened'
  ) RETURNING id INTO v_request_alpha;

  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  SELECT create_quotation(
    v_customer_alpha, v_request_alpha, '2026-08-20', 'teste', NULL,
    '[{"kind":"service","description":"Instalacao","quantity":1,"unit_price_cents":25000,"unit_cost_cents":10000}]'::jsonb
  ) INTO v_quote;
  v_quotation_id := (v_quote->>'id')::uuid;

  RESET role;
  UPDATE quotations SET status = 'approved' WHERE id = v_quotation_id;

  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);
  SELECT convert_approved_quotation_to_work_order(v_quotation_id) INTO v_wo;
  v_wo_id := (v_wo->>'id')::uuid;

  v_path_ok := :'TENANT_ALPHA' || '/' || v_wo_id::text || '/evidencia-teste.png';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T1: evidencia registrada com caminho valido (tenant_id/work_order_id/...)
  -- ─────────────────────────────────────────────────────────────────────────
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_TECH')::text, true);

  SELECT record_work_order_evidence(v_wo_id, 'photo', v_path_ok, 'image/png', 1024)
  INTO v_evidence;

  SELECT COUNT(*) INTO v_count FROM work_order_evidence WHERE work_order_id = v_wo_id;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FALHOU T1: evidencia nao foi registrada (count=%)', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T1: evidencia registrada (id=%)', v_evidence->>'id';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T2: caminho fora do escopo tenant/OS e bloqueado
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM record_work_order_evidence(
      v_wo_id, 'photo', 'outro-tenant/outro-wo/arquivo.png', 'image/png', 1024
    );
    RAISE EXCEPTION 'FALHOU T2: caminho de storage fora do escopo foi aceito';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T2: caminho de storage fora do escopo foi bloqueado';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T3: tipo de evidencia invalido e bloqueado
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM record_work_order_evidence(v_wo_id, 'audio', v_path_ok, 'audio/mp3', 1024);
    RAISE EXCEPTION 'FALHOU T3: tipo de evidencia invalido foi aceito';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T3: tipo de evidencia invalido foi bloqueado';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T4: arquivo acima do limite de tamanho e bloqueado (> 50 MiB)
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM record_work_order_evidence(v_wo_id, 'photo', v_path_ok, 'image/png', 52428801);
    RAISE EXCEPTION 'FALHOU T4: arquivo acima do limite foi aceito';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T4: arquivo acima do limite foi bloqueado';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T5: isolamento — beta nao registra evidencia na OS do alpha
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_BETA')::text, true);

  BEGIN
    PERFORM record_work_order_evidence(v_wo_id, 'photo', v_path_ok, 'image/png', 1024);
    RAISE EXCEPTION 'FALHOU T5: beta_owner registrou evidencia na OS do tenant alpha';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T5: beta_owner nao registra evidencia na OS do tenant alpha';
  END;

  RAISE NOTICE '=== Testes E7 (evidencia) concluidos ===';
  RAISE EXCEPTION 'ROLLBACK_TEST_DATA' USING DETAIL = 'Dados de teste removidos.';

EXCEPTION
  WHEN SQLSTATE 'P0001' AND SQLERRM = 'ROLLBACK_TEST_DATA' THEN
    RAISE NOTICE 'Dados de teste revertidos (rollback intencional).';
END;
$$;

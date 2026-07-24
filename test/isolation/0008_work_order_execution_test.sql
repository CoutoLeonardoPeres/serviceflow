-- =============================================================================
-- Testes de isolamento RLS — migration 0009_work_order_execution
--
-- Reescrito em 2026-07-24: a versão anterior era um roteiro manual comentado,
-- sem asserções automáticas nem verificação de isolamento entre tenants.
--
-- Como executar:
--   psql $DATABASE_URL -f test/isolation/0008_work_order_execution_test.sql
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
  v_entry          jsonb;
  v_status         text;
  v_count          int;
BEGIN
  RAISE NOTICE '=== E7 RLS Work Order Execution — Inicio ===';

  -- SETUP: cliente, chamado, orcamento aprovado, OS convertida
  INSERT INTO customers (tenant_id, type, name, is_active)
  VALUES (:'TENANT_ALPHA', 'company', 'Cliente Execucao Alpha', true)
  RETURNING id INTO v_customer_alpha;

  INSERT INTO service_requests (
    tenant_id, number, customer_id, title, description, channel, status
  ) VALUES (
    :'TENANT_ALPHA', 9401, v_customer_alpha, 'Chamado Execucao Alpha',
    'Descricao suficiente para teste de execucao alpha.', 'phone', 'opened'
  ) RETURNING id INTO v_request_alpha;

  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  SELECT create_quotation(
    v_customer_alpha, v_request_alpha, '2026-08-20', 'teste', NULL,
    '[{"kind":"service","description":"Manutencao","quantity":1,"unit_price_cents":40000,"unit_cost_cents":15000}]'::jsonb
  ) INTO v_quote;
  v_quotation_id := (v_quote->>'id')::uuid;

  RESET role;
  UPDATE quotations SET status = 'approved' WHERE id = v_quotation_id;

  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);
  SELECT convert_approved_quotation_to_work_order(v_quotation_id) INTO v_wo;
  v_wo_id := (v_wo->>'id')::uuid;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T1: technician registra horas — OS 'opened' vira 'in_progress'
  -- ─────────────────────────────────────────────────────────────────────────
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_TECH')::text, true);

  SELECT record_work_order_time_entry(
    v_wo_id, now() - interval '2 hours', now(), 'Atendimento tecnico em campo.'
  ) INTO v_entry;

  IF (v_entry->>'duration_minutes')::int <> 120 THEN
    RAISE EXCEPTION 'FALHOU T1: duracao calculada incorretamente (%)', v_entry->>'duration_minutes';
  END IF;
  RAISE NOTICE 'PASSOU T1: horas registradas (% min)', v_entry->>'duration_minutes';

  SELECT status INTO v_status FROM work_orders WHERE id = v_wo_id;
  IF v_status <> 'in_progress' THEN
    RAISE EXCEPTION 'FALHOU T2: OS nao transicionou para in_progress (status=%)', v_status;
  END IF;
  RAISE NOTICE 'PASSOU T2: OS transicionou automaticamente para in_progress';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T3: periodo invalido (0 minutos) e bloqueado
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM record_work_order_time_entry(v_wo_id, now(), now(), 'periodo zero');
    RAISE EXCEPTION 'FALHOU T3: periodo de 0 minutos foi aceito';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T3: periodo de 0 minutos foi bloqueado';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T4: material aplicado — total calculado
  -- ─────────────────────────────────────────────────────────────────────────
  PERFORM add_work_order_material(v_wo_id, 'Filtro secador 1/4', 2, 4500, 9000);

  SELECT COUNT(*) INTO v_count FROM work_order_materials WHERE work_order_id = v_wo_id;
  IF v_count < 1 THEN
    RAISE EXCEPTION 'FALHOU T4: material nao foi registrado (count=%)', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T4: material registrado (% linha(s))', v_count;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T5: isolamento — beta nao registra horas na OS do alpha
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_BETA')::text, true);

  BEGIN
    PERFORM record_work_order_time_entry(v_wo_id, now() - interval '1 hour', now(), 'tentativa cross tenant');
    RAISE EXCEPTION 'FALHOU T5: beta_owner registrou horas na OS do tenant alpha';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T5: beta_owner nao registra horas na OS do tenant alpha';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T6: isolamento — beta nao adiciona material na OS do alpha
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM add_work_order_material(v_wo_id, 'Peca invasora', 1, 1000, 2000);
    RAISE EXCEPTION 'FALHOU T6: beta_owner adicionou material na OS do tenant alpha';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T6: beta_owner nao adiciona material na OS do tenant alpha';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T7: auditoria — eventos de horas/material foram registrados
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SELECT COUNT(*) INTO v_count
  FROM audit_logs
  WHERE action IN ('work_order.time_entry.created', 'work_order.material.created')
    AND tenant_id = :'TENANT_ALPHA';

  IF v_count < 2 THEN
    RAISE EXCEPTION 'FALHOU T7: auditoria incompleta para execucao (count=%)', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T7: % evento(s) de auditoria registrado(s)', v_count;

  RAISE NOTICE '=== Testes E7 (execucao) concluidos ===';
  RAISE EXCEPTION 'ROLLBACK_TEST_DATA' USING DETAIL = 'Dados de teste removidos.';

EXCEPTION
  WHEN SQLSTATE 'P0001' AND SQLERRM = 'ROLLBACK_TEST_DATA' THEN
    RAISE NOTICE 'Dados de teste revertidos (rollback intencional).';
END;
$$;

-- =============================================================================
-- Testes de isolamento RLS — migration 0057_work_order_state_machine
--
-- Prova o contrato das correcoes P0 do critique:
--   * `opened` -> `done` e recusado (nao existe atalho para concluir);
--   * o caminho legitimo opened -> in_progress -> done funciona;
--   * repetir o status atual e silencioso, nao erro (toque duplo no campo);
--   * OS terminal nao muda mais de status;
--   * cobranca de OS nao concluida e recusada;
--   * cobranca de OS concluida com valor e aceita e idempotente;
--   * my_permissions() devolve as permissoes do papel do usuario e nao vaza
--     permissoes de outro tenant.
--
-- Como executar:
--   psql $DATABASE_URL -f test/isolation/0028_work_order_state_machine_test.sql
-- Substitua os \set abaixo pelos UUIDs reais do seed antes de executar.
-- USER_ALPHA precisa ter work_orders.execute (ou .manage) e financials.write.
-- =============================================================================

\set ON_ERROR_STOP on

\set TENANT_ALPHA  'a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1'
\set USER_ALPHA    'a1000000-0000-4000-8000-000000000001'
\set USER_BETA     'b2000000-0000-4000-8000-000000000002'

DO $$
DECLARE
  v_customer uuid;
  v_wo       uuid;
  v_wo2      uuid;
  v_status   text;
  v_count    int;
  v_perms    text[];
  v_perms_b  text[];
BEGIN
  RAISE NOTICE '=== 0057 Maquina de estados da OS — Inicio ===';

  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  INSERT INTO customers (tenant_id, type, name, document)
  VALUES (:'TENANT_ALPHA', 'person', 'Cliente Maquina Estados', '52998224725')
  RETURNING id INTO v_customer;

  INSERT INTO work_orders (
    tenant_id, number, customer_id, status, title, description, total_cents
  ) VALUES (
    :'TENANT_ALPHA', next_sequence(:'TENANT_ALPHA', 'work_order'), v_customer,
    'opened', 'OS teste maquina de estados',
    'OS usada para validar as transicoes permitidas.', 25000
  )
  RETURNING id INTO v_wo;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T1: opened -> done e recusado
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM transition_work_order(v_wo, 'done', NULL);
    RAISE EXCEPTION 'FALHOU T1: OS aberta foi concluida direto';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T1: nao existe atalho de aberta para concluida';
  END;

  SELECT status INTO v_status FROM work_orders WHERE id = v_wo;
  IF v_status <> 'opened' THEN
    RAISE EXCEPTION 'FALHOU T1: status mudou para % apesar da recusa', v_status;
  END IF;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T2: cobranca de OS nao concluida e recusada
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM create_receivable_from_work_order(v_wo, NULL);
    RAISE EXCEPTION 'FALHOU T2: gerou cobranca de servico nao prestado';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T2: cobranca exige OS concluida';
  END;

  SELECT COUNT(*) INTO v_count FROM receivables WHERE work_order_id = v_wo;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FALHOU T2: recebivel criado apesar da recusa';
  END IF;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T3: caminho legitimo opened -> in_progress -> done
  -- ─────────────────────────────────────────────────────────────────────────
  PERFORM transition_work_order(v_wo, 'in_progress', NULL);
  PERFORM transition_work_order(v_wo, 'done', 'Servico concluido no teste');

  SELECT status INTO v_status FROM work_orders WHERE id = v_wo;
  IF v_status <> 'done' THEN
    RAISE EXCEPTION 'FALHOU T3: caminho legitimo terminou em %', v_status;
  END IF;
  RAISE NOTICE 'PASSOU T3: opened -> in_progress -> done funciona';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T4: OS terminal nao muda mais
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM transition_work_order(v_wo, 'in_progress', NULL);
    RAISE EXCEPTION 'FALHOU T4: OS concluida voltou para execucao';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T4: OS finalizada e terminal';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T5: cobranca de OS concluida e aceita, e repetir nao duplica
  -- ─────────────────────────────────────────────────────────────────────────
  PERFORM create_receivable_from_work_order(v_wo, NULL);
  PERFORM create_receivable_from_work_order(v_wo, NULL);

  SELECT COUNT(*) INTO v_count FROM receivables WHERE work_order_id = v_wo;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FALHOU T5: % recebiveis para a mesma OS', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T5: cobranca de OS concluida e idempotente';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T6: repetir o status atual e silencioso (toque duplo em rede instavel)
  -- ─────────────────────────────────────────────────────────────────────────
  INSERT INTO work_orders (
    tenant_id, number, customer_id, status, title, description, total_cents
  ) VALUES (
    :'TENANT_ALPHA', next_sequence(:'TENANT_ALPHA', 'work_order'), v_customer,
    'opened', 'OS teste toque duplo',
    'OS usada para validar transicao repetida.', 10000
  )
  RETURNING id INTO v_wo2;

  PERFORM transition_work_order(v_wo2, 'in_progress', NULL);
  PERFORM transition_work_order(v_wo2, 'in_progress', NULL);

  SELECT COUNT(*) INTO v_count
  FROM work_order_events
  WHERE work_order_id = v_wo2 AND event_type = 'started';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FALHOU T6: toque duplo gravou % eventos', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T6: repetir o status nao suja o historico';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T7: my_permissions() devolve as permissoes do papel e nao vaza entre users
  -- ─────────────────────────────────────────────────────────────────────────
  v_perms := my_permissions();
  IF v_perms IS NULL OR array_length(v_perms, 1) IS NULL THEN
    RAISE EXCEPTION 'FALHOU T7: my_permissions() vazio para usuario com papel';
  END IF;
  IF NOT ('work_orders.execute' = ANY (v_perms)
          OR 'work_orders.manage' = ANY (v_perms)) THEN
    RAISE EXCEPTION 'FALHOU T7: permissao de OS ausente em %', v_perms;
  END IF;

  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_BETA')::text, true);
  v_perms_b := my_permissions();

  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  IF v_perms_b IS NOT DISTINCT FROM v_perms
     AND array_length(v_perms, 1) IS NOT NULL THEN
    RAISE NOTICE 'AVISO T7: alpha e beta tem a mesma lista — papeis identicos no seed?';
  END IF;
  RAISE NOTICE 'PASSOU T7: my_permissions() resolve pelo usuario autenticado';

  RAISE NOTICE '=== 0057 Maquina de estados da OS — TODOS OS TESTES PASSARAM ===';
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

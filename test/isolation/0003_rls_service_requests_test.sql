-- =============================================================================
-- Testes de isolamento RLS — migration 0003_service_requests
-- Como executar:
--   1. supabase start
--   2. supabase db reset
--   3. psql $DATABASE_URL -f supabase/seed/dev_seed.sql
--   4. psql $DATABASE_URL -f test/isolation/0003_rls_service_requests_test.sql
--
-- Substitua os UUIDs pelos usuarios/tenants reais do seed local.
-- =============================================================================

\set ON_ERROR_STOP on

\set TENANT_ALPHA  'a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1'
\set TENANT_BETA   'b2b2b2b2-b2b2-4b2b-b2b2-b2b2b2b2b2b2'
\set USER_ALPHA    'a1000000-0000-4000-8000-000000000001'
\set USER_BETA     'b2000000-0000-4000-8000-000000000002'
\set USER_TECH     'a1000000-0000-4000-8000-000000000003'
\set USER_VIEWER   'a1000000-0000-4000-8000-000000000004'

DO $$
DECLARE
  v_customer_alpha uuid;
  v_customer_beta uuid;
  v_request_alpha uuid;
  v_request_beta uuid;
  v_count int;
BEGIN
  RAISE NOTICE '=== E4 RLS Service Requests — Inicio ===';

  SET LOCAL role = authenticated;
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', :'USER_ALPHA')::text,
    true
  );
  INSERT INTO customers (tenant_id, type, name, is_active)
  VALUES (:'TENANT_ALPHA', 'company', 'Cliente Chamado Alpha', true)
  RETURNING id INTO v_customer_alpha;

  SET LOCAL role = authenticated;
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', :'USER_BETA')::text,
    true
  );
  INSERT INTO customers (tenant_id, type, name, is_active)
  VALUES (:'TENANT_BETA', 'company', 'Cliente Chamado Beta', true)
  RETURNING id INTO v_customer_beta;

  SET LOCAL role = authenticated;
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', :'USER_ALPHA')::text,
    true
  );
  INSERT INTO service_requests (
    tenant_id, number, customer_id, title, description, channel, status
  ) VALUES (
    :'TENANT_ALPHA', 9001, v_customer_alpha, 'Chamado Alpha',
    'Descricao suficiente para teste alpha.', 'phone', 'opened'
  ) RETURNING id INTO v_request_alpha;

  SET LOCAL role = authenticated;
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', :'USER_BETA')::text,
    true
  );
  INSERT INTO service_requests (
    tenant_id, number, customer_id, title, description, channel, status
  ) VALUES (
    :'TENANT_BETA', 9001, v_customer_beta, 'Chamado Beta',
    'Descricao suficiente para teste beta.', 'phone', 'opened'
  ) RETURNING id INTO v_request_beta;

  SET LOCAL role = authenticated;
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', :'USER_ALPHA')::text,
    true
  );

  SELECT COUNT(*) INTO v_count
  FROM service_requests
  WHERE tenant_id = :'TENANT_BETA';

  IF v_count > 0 THEN
    RAISE EXCEPTION 'FALHOU T1: alpha viu % chamado(s) beta', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T1: alpha nao le chamados beta';

  SELECT COUNT(*) INTO v_count
  FROM service_requests
  WHERE tenant_id = :'TENANT_ALPHA';

  IF v_count < 1 THEN
    RAISE EXCEPTION 'FALHOU T2: alpha nao viu chamados proprios';
  END IF;
  RAISE NOTICE 'PASSOU T2: alpha le chamados proprios';

  SET LOCAL role = authenticated;
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', :'USER_VIEWER')::text,
    true
  );

  BEGIN
    INSERT INTO service_requests (customer_id, title, description, channel)
    VALUES (
      v_customer_alpha,
      'Tentativa viewer',
      'Viewer nao deve criar chamados neste teste.',
      'phone'
    );
    RAISE EXCEPTION 'FALHOU T3: viewer criou chamado';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T3: viewer nao cria chamados';
  END;

  SET LOCAL role = authenticated;
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', :'USER_BETA')::text,
    true
  );

  BEGIN
    INSERT INTO service_requests (customer_id, title, description, channel)
    VALUES (
      v_customer_alpha,
      'Tentativa cross tenant',
      'Beta nao deve criar chamado para cliente alpha.',
      'phone'
    );
    RAISE EXCEPTION 'FALHOU T4: beta criou chamado para cliente alpha';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T4: beta nao cria chamado em cliente alpha';
  END;

  SET LOCAL role = authenticated;
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', :'USER_TECH')::text,
    true
  );

  -- RLS em UPDATE filtra a linha silenciosamente (0 rows), não lança
  -- insufficient_privilege — checar ROW_COUNT em vez de exceção.
  UPDATE service_requests SET title = 'Alterado por tecnico'
  WHERE id = v_request_alpha;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  IF v_count > 0 THEN
    RAISE EXCEPTION 'FALHOU T5: tecnico editou chamado';
  END IF;
  RAISE NOTICE 'PASSOU T5: tecnico nao edita chamado';

  RESET role;

  SELECT COUNT(*) INTO v_count
  FROM service_request_status_history
  WHERE request_id = v_request_alpha
    AND to_status = 'opened';

  IF v_count < 1 THEN
    RAISE EXCEPTION 'FALHOU T6: chamado sem historico inicial';
  END IF;
  RAISE NOTICE 'PASSOU T6: historico inicial criado';

  SELECT COUNT(*) INTO v_count
  FROM audit_logs
  WHERE action = 'service_request.created'
    AND tenant_id = :'TENANT_ALPHA';

  IF v_count < 1 THEN
    RAISE EXCEPTION 'FALHOU T7: chamado sem auditoria';
  END IF;
  RAISE NOTICE 'PASSOU T7: auditoria criada';

  RAISE NOTICE '=== Testes E4 concluidos ===';
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

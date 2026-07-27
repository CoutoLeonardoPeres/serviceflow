-- =============================================================================
-- Testes de isolamento RLS — migration 0005_quotations
-- Substitua UUIDs por usuarios/tenants reais do seed antes de executar.
-- =============================================================================

\set ON_ERROR_STOP on

\set TENANT_ALPHA  'a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1'
\set TENANT_BETA   'b2b2b2b2-b2b2-4b2b-b2b2-b2b2b2b2b2b2'
\set USER_ALPHA    'a1000000-0000-4000-8000-000000000001'
\set USER_BETA     'b2000000-0000-4000-8000-000000000002'

DO $$
DECLARE
  v_customer_alpha uuid;
  v_customer_beta uuid;
  v_request_alpha uuid;
  v_quote jsonb;
  v_count int;
BEGIN
  RAISE NOTICE '=== E6 RLS Quotations — Inicio ===';

  SET LOCAL role = authenticated;
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', :'USER_ALPHA')::text,
    true
  );
  INSERT INTO customers (tenant_id, type, name, is_active)
  VALUES (:'TENANT_ALPHA', 'company', 'Cliente Orcamento Alpha', true)
  RETURNING id INTO v_customer_alpha;

  SET LOCAL role = authenticated;
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', :'USER_BETA')::text,
    true
  );
  INSERT INTO customers (tenant_id, type, name, is_active)
  VALUES (:'TENANT_BETA', 'company', 'Cliente Orcamento Beta', true)
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
    :'TENANT_ALPHA', 9201, v_customer_alpha, 'Chamado Orcamento Alpha',
    'Descricao suficiente para teste de orcamento alpha.', 'phone', 'opened'
  ) RETURNING id INTO v_request_alpha;

  SET LOCAL role = authenticated;
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', :'USER_ALPHA')::text,
    true
  );

  SELECT create_quotation(
    v_customer_alpha,
    v_request_alpha,
    '2026-08-20',
    'teste',
    NULL,
    '[{"kind":"service","description":"Instalacao","quantity":2,"unit_price_cents":15000,"unit_cost_cents":8000}]'::jsonb
  ) INTO v_quote;

  IF (v_quote->>'total_cents')::int <> 30000 THEN
    RAISE EXCEPTION 'FALHOU T1: total calculado incorretamente';
  END IF;
  RAISE NOTICE 'PASSOU T1: orcamento criado com total server-side';

  SET LOCAL role = authenticated;
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', :'USER_BETA')::text,
    true
  );

  SELECT COUNT(*) INTO v_count
  FROM quotations
  WHERE tenant_id = :'TENANT_ALPHA';

  IF v_count > 0 THEN
    RAISE EXCEPTION 'FALHOU T2: beta viu orcamento alpha';
  END IF;
  RAISE NOTICE 'PASSOU T2: beta nao ve orcamento alpha';

  BEGIN
    PERFORM create_quotation(
      v_customer_alpha,
      v_request_alpha,
      '2026-08-20',
      'cross tenant',
      NULL,
      '[{"kind":"service","description":"Teste","quantity":1,"unit_price_cents":10000,"unit_cost_cents":5000}]'::jsonb
    );
    RAISE EXCEPTION 'FALHOU T3: beta criou orcamento alpha';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T3: beta nao cria orcamento alpha';
  END;

  RESET role;
  RAISE NOTICE '=== Testes E6 concluidos ===';
  RAISE EXCEPTION 'ROLLBACK_TEST_DATA' USING DETAIL = 'Dados removidos.';

EXCEPTION
  WHEN SQLSTATE 'P0001' THEN
    IF SQLERRM = 'ROLLBACK_TEST_DATA' THEN
      RAISE NOTICE 'Dados de teste revertidos (rollback intencional).';
    ELSE
      RAISE;
    END IF;
END;
$$;

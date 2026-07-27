-- =============================================================================
-- Testes de isolamento RLS — migration 0004_scheduling
-- Substitua UUIDs por usuarios/tenants reais do seed antes de executar.
-- =============================================================================

\set ON_ERROR_STOP on

\set TENANT_ALPHA  'a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1'
\set TENANT_BETA   'b2b2b2b2-b2b2-4b2b-b2b2-b2b2b2b2b2b2'
\set USER_ALPHA    'a1000000-0000-4000-8000-000000000001'
\set USER_BETA     'b2000000-0000-4000-8000-000000000002'
\set USER_TECH     'a1000000-0000-4000-8000-000000000003'

DO $$
DECLARE
  v_customer_alpha uuid;
  v_customer_beta uuid;
  v_request_alpha uuid;
  v_appointment uuid;
  v_count int;
BEGIN
  RAISE NOTICE '=== E5 RLS Scheduling — Inicio ===';

  SET LOCAL role = authenticated;
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', :'USER_ALPHA')::text,
    true
  );
  INSERT INTO customers (tenant_id, type, name, is_active)
  VALUES (:'TENANT_ALPHA', 'company', 'Cliente Agenda Alpha', true)
  RETURNING id INTO v_customer_alpha;

  SET LOCAL role = authenticated;
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', :'USER_BETA')::text,
    true
  );
  INSERT INTO customers (tenant_id, type, name, is_active)
  VALUES (:'TENANT_BETA', 'company', 'Cliente Agenda Beta', true)
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
    :'TENANT_ALPHA', 9101, v_customer_alpha, 'Chamado Agenda Alpha',
    'Descricao suficiente para teste agenda alpha.', 'phone', 'opened'
  ) RETURNING id INTO v_request_alpha;

  SET LOCAL role = authenticated;
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', :'USER_ALPHA')::text,
    true
  );

  SELECT schedule_appointment(
    'visit',
    v_request_alpha,
    v_customer_alpha,
    NULL,
    '2026-07-22 13:00:00+00',
    '2026-07-22 15:00:00+00',
    :'USER_TECH',
    'teste'
  ) INTO v_appointment;

  IF v_appointment IS NULL THEN
    RAISE EXCEPTION 'FALHOU T1: agendamento nao foi criado';
  END IF;
  RAISE NOTICE 'PASSOU T1: agendamento criado';

  BEGIN
    PERFORM schedule_appointment(
      'visit',
      v_request_alpha,
      v_customer_alpha,
      NULL,
      '2026-07-22 14:00:00+00',
      '2026-07-22 16:00:00+00',
      :'USER_TECH',
      'conflito'
    );
    RAISE EXCEPTION 'FALHOU T2: conflito de agenda foi permitido';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T2: conflito de agenda bloqueado';
  END;

  SET LOCAL role = authenticated;
  PERFORM set_config(
    'request.jwt.claims',
    json_build_object('sub', :'USER_BETA')::text,
    true
  );

  SELECT COUNT(*) INTO v_count
  FROM appointments
  WHERE tenant_id = :'TENANT_ALPHA';

  IF v_count > 0 THEN
    RAISE EXCEPTION 'FALHOU T3: beta viu agenda alpha';
  END IF;
  RAISE NOTICE 'PASSOU T3: beta nao ve agenda alpha';

  BEGIN
    PERFORM schedule_appointment(
      'visit',
      v_request_alpha,
      v_customer_alpha,
      NULL,
      '2026-07-23 13:00:00+00',
      '2026-07-23 15:00:00+00',
      :'USER_TECH',
      'cross tenant'
    );
    RAISE EXCEPTION 'FALHOU T4: beta agendou chamado alpha';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T4: beta nao agenda chamado alpha';
  END;

  RESET role;

  SELECT COUNT(*) INTO v_count
  FROM technical_visits
  WHERE appointment_id = v_appointment
    AND request_id = v_request_alpha;

  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FALHOU T5: visita tecnica nao criada';
  END IF;
  RAISE NOTICE 'PASSOU T5: visita tecnica criada';

  RAISE NOTICE '=== Testes E5 concluidos ===';
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

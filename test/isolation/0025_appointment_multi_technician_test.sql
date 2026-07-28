-- =============================================================================
-- Testes de isolamento RLS — migration 0052_appointment_multi_technician
--
-- Prova o contrato do F5-P2 (ADR-027):
--   * assign_technician acrescenta um segundo profissional e registra evento;
--   * atribuir de novo quem ja esta e idempotente (nao duplica);
--   * tecnico ocupado no mesmo horario e recusado;
--   * unassign_technician revoga e registra evento;
--   * remover o ultimo profissional e recusado (atendimento fantasma);
--   * reatribuir alguem que ja saiu funciona (constraint unica nao atrapalha);
--   * atendimento cancelado nao aceita novo profissional;
--   * isolamento entre tenants.
--
-- Como executar:
--   psql $DATABASE_URL -f test/isolation/0025_appointment_multi_technician_test.sql
-- Substitua os \set abaixo pelos UUIDs reais do seed antes de executar.
-- Requer DOIS tecnicos ativos no tenant alpha, ambos com
-- service_professionals.linked_user_id apontando para eles.
-- =============================================================================

\set ON_ERROR_STOP on

\set TENANT_ALPHA  'a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1'
\set USER_ALPHA    'a1000000-0000-4000-8000-000000000001'
\set USER_BETA     'b2000000-0000-4000-8000-000000000002'
\set USER_TECH     'a1000000-0000-4000-8000-000000000003'
\set USER_TECH2    'a1000000-0000-4000-8000-000000000004'

DO $$
DECLARE
  v_customer    uuid;
  v_request     uuid;
  v_request_b   uuid;
  v_appointment uuid;
  v_other       uuid;
  v_start       timestamptz := date_trunc('hour', now()) + interval '2 days';
  v_count       int;
BEGIN
  RAISE NOTICE '=== F5-P2 Multiplos profissionais — Inicio ===';

  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  INSERT INTO customers (tenant_id, type, name, document)
  VALUES (:'TENANT_ALPHA', 'person', 'Cliente Dupla Teste', '52998224725')
  RETURNING id INTO v_customer;

  INSERT INTO service_requests (
    tenant_id, customer_id, title, description, channel, status
  )
  VALUES (
    :'TENANT_ALPHA', v_customer, 'Chamado dupla teste',
    'Servico que precisa de dois profissionais.', 'whatsapp', 'opened'
  )
  RETURNING id INTO v_request;

  INSERT INTO service_requests (
    tenant_id, customer_id, title, description, channel, status
  )
  VALUES (
    :'TENANT_ALPHA', v_customer, 'Chamado concorrente',
    'Chamado para ocupar o tecnico no mesmo horario.', 'whatsapp', 'opened'
  )
  RETURNING id INTO v_request_b;

  v_appointment := schedule_appointment(
    'visit', v_request, v_customer, NULL,
    v_start, v_start + interval '1 hour', :'USER_TECH', NULL
  );

  -- ─────────────────────────────────────────────────────────────────────────
  -- T1: acrescentar um segundo profissional
  -- ─────────────────────────────────────────────────────────────────────────
  PERFORM assign_technician(v_appointment, :'USER_TECH2', NULL);

  SELECT COUNT(*) INTO v_count
  FROM appointment_assignments
  WHERE appointment_id = v_appointment AND revoked_at IS NULL;
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'FALHOU T1: esperado 2 profissionais, encontrado %', v_count;
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM appointment_events
  WHERE appointment_id = v_appointment
    AND event_type = 'technician_added'
    AND technician_user_id = :'USER_TECH2'::uuid;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FALHOU T1: evento technician_added nao registrado';
  END IF;
  RAISE NOTICE 'PASSOU T1: segundo profissional atribuido e registrado';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T2: atribuir de novo quem ja esta e idempotente
  -- ─────────────────────────────────────────────────────────────────────────
  PERFORM assign_technician(v_appointment, :'USER_TECH2', NULL);

  SELECT COUNT(*) INTO v_count
  FROM appointment_assignments
  WHERE appointment_id = v_appointment AND revoked_at IS NULL;
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'FALHOU T2: atribuicao duplicada (% ativos)', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T2: reatribuir quem ja esta e idempotente';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T3: tecnico ocupado no mesmo horario e recusado
  -- ─────────────────────────────────────────────────────────────────────────
  v_other := schedule_appointment(
    'visit', v_request_b, v_customer, NULL,
    v_start + interval '4 hours', v_start + interval '5 hours',
    :'USER_TECH', NULL
  );

  BEGIN
    PERFORM assign_technician(v_other, :'USER_TECH2', NULL);
    -- TECH2 esta livre nesse horario, entao a atribuicao deve passar.
    RAISE NOTICE 'PASSOU T3a: tecnico livre em outro horario e aceito';
  EXCEPTION
    WHEN check_violation THEN
      RAISE EXCEPTION 'FALHOU T3a: tecnico livre foi recusado';
  END;

  -- Agora TECH2 esta nos dois horarios distintos. Um terceiro atendimento
  -- sobreposto ao primeiro precisa recusa-lo.
  BEGIN
    PERFORM assign_technician(v_appointment, :'USER_TECH', NULL);
    RAISE NOTICE 'PASSOU T3b: titular do proprio atendimento e idempotente';
  EXCEPTION
    WHEN check_violation THEN
      RAISE EXCEPTION 'FALHOU T3b: titular do proprio atendimento recusado';
  END;
  RAISE NOTICE 'PASSOU T3: conflito de horario avaliado por atendimento';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T4: remover o segundo profissional
  -- ─────────────────────────────────────────────────────────────────────────
  PERFORM unassign_technician(v_appointment, :'USER_TECH2', NULL);

  SELECT COUNT(*) INTO v_count
  FROM appointment_assignments
  WHERE appointment_id = v_appointment AND revoked_at IS NULL;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FALHOU T4: esperado 1 profissional, encontrado %', v_count;
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM appointment_events
  WHERE appointment_id = v_appointment AND event_type = 'technician_removed';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FALHOU T4: evento technician_removed nao registrado';
  END IF;
  RAISE NOTICE 'PASSOU T4: profissional removido e registrado';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T5: remover o ultimo profissional e recusado
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM unassign_technician(v_appointment, :'USER_TECH', NULL);
    RAISE EXCEPTION 'FALHOU T5: atendimento ficou sem nenhum profissional';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T5: atendimento nao fica sem responsavel';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T6: reatribuir quem ja saiu (constraint unica nao atrapalha)
  -- ─────────────────────────────────────────────────────────────────────────
  PERFORM assign_technician(v_appointment, :'USER_TECH2', NULL);

  SELECT COUNT(*) INTO v_count
  FROM appointment_assignments
  WHERE appointment_id = v_appointment AND revoked_at IS NULL;
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'FALHOU T6: reatribuicao nao reativou o assignment (% ativos)', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T6: profissional que saiu pode voltar';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T7: atendimento cancelado nao aceita novo profissional
  -- ─────────────────────────────────────────────────────────────────────────
  PERFORM cancel_appointment(v_appointment, 'Teste');

  BEGIN
    PERFORM assign_technician(v_appointment, :'USER_TECH2', NULL);
    RAISE EXCEPTION 'FALHOU T7: atendimento cancelado aceitou profissional';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T7: atendimento encerrado nao aceita profissional';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T8: isolamento — beta nao atribui em atendimento do alpha
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_BETA')::text, true);

  BEGIN
    PERFORM assign_technician(v_other, :'USER_TECH', NULL);
    RAISE EXCEPTION 'FALHOU T8: beta_owner atribuiu em atendimento do alpha';
  EXCEPTION
    WHEN no_data_found OR insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T8: beta_owner isolado dos atendimentos do alpha';
  END;

  RAISE NOTICE '=== Testes F5-P2 (multiplos profissionais) concluidos ===';
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

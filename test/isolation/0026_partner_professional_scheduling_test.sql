-- =============================================================================
-- Testes de isolamento RLS — migration 0053_schedule_partner_professionals
--
-- Prova o contrato do F5-P4 (ADR-028):
--   * profissional SEM linked_user_id e agendavel;
--   * o assignment fica com technician_user_id nulo e professional_id cheio;
--   * conflito de horario e avaliado por profissional, nao por usuario;
--   * parceiro entra como segundo profissional de um atendimento;
--   * profissional inativo e recusado;
--   * technical_visits aceita visita sem tecnico com login;
--   * isolamento entre tenants.
--
-- Como executar:
--   psql $DATABASE_URL -f test/isolation/0026_partner_professional_scheduling_test.sql
-- Substitua os \set abaixo pelos UUIDs reais do seed antes de executar.
-- =============================================================================

\set ON_ERROR_STOP on

\set TENANT_ALPHA  'a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1'
\set TENANT_BETA   'b2b2b2b2-b2b2-4b2b-b2b2-b2b2b2b2b2b2'
\set USER_ALPHA    'a1000000-0000-4000-8000-000000000001'
\set USER_BETA     'b2000000-0000-4000-8000-000000000002'

DO $$
DECLARE
  v_customer     uuid;
  v_request      uuid;
  v_request_b    uuid;
  v_partner      uuid;
  v_partner_2    uuid;
  v_inactive     uuid;
  v_appointment  uuid;
  v_other        uuid;
  v_start        timestamptz := date_trunc('hour', now()) + interval '3 days';
  v_count        int;
  v_user_id      uuid;
BEGIN
  RAISE NOTICE '=== F5-P4 Parceiro sem usuario — Inicio ===';

  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  INSERT INTO customers (tenant_id, type, name, document)
  VALUES (:'TENANT_ALPHA', 'person', 'Cliente Parceiro Teste', '52998224725')
  RETURNING id INTO v_customer;

  INSERT INTO service_requests (
    tenant_id, customer_id, title, description, channel, status
  )
  VALUES (
    :'TENANT_ALPHA', v_customer, 'Chamado parceiro teste',
    'Atendimento executado por parceiro externo.', 'whatsapp', 'opened'
  )
  RETURNING id INTO v_request;

  INSERT INTO service_requests (
    tenant_id, customer_id, title, description, channel, status
  )
  VALUES (
    :'TENANT_ALPHA', v_customer, 'Chamado parceiro concorrente',
    'Segundo chamado, para testar conflito de horario.', 'whatsapp', 'opened'
  )
  RETURNING id INTO v_request_b;

  -- Parceiros externos: sem linked_user_id, exatamente o caso que a 0053
  -- passou a permitir.
  INSERT INTO service_professionals (tenant_id, kind, category, name, is_active)
  VALUES (:'TENANT_ALPHA', 'partner', 'Eletricista', 'Parceiro Externo Um', true)
  RETURNING id INTO v_partner;

  INSERT INTO service_professionals (tenant_id, kind, category, name, is_active)
  VALUES (:'TENANT_ALPHA', 'partner', 'Ajudante', 'Parceiro Externo Dois', true)
  RETURNING id INTO v_partner_2;

  INSERT INTO service_professionals (tenant_id, kind, category, name, is_active)
  VALUES (:'TENANT_ALPHA', 'partner', 'Pintor', 'Parceiro Inativo', false)
  RETURNING id INTO v_inactive;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T1: agendar parceiro sem usuario do sistema
  -- ─────────────────────────────────────────────────────────────────────────
  v_appointment := schedule_appointment(
    'visit', v_request, v_customer, NULL,
    v_start, v_start + interval '1 hour', NULL, NULL, v_partner
  );

  SELECT COUNT(*) INTO v_count
  FROM appointment_assignments
  WHERE appointment_id = v_appointment
    AND professional_id = v_partner
    AND technician_user_id IS NULL
    AND revoked_at IS NULL;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FALHOU T1: assignment do parceiro nao criado corretamente';
  END IF;
  RAISE NOTICE 'PASSOU T1: parceiro sem usuario foi agendado';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T2: a visita tecnica existe mesmo sem tecnico com login
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT technician_id INTO v_user_id
  FROM technical_visits WHERE appointment_id = v_appointment;

  SELECT COUNT(*) INTO v_count
  FROM technical_visits WHERE appointment_id = v_appointment;
  IF v_count <> 1 OR v_user_id IS NOT NULL THEN
    RAISE EXCEPTION 'FALHOU T2: technical_visits inconsistente para parceiro';
  END IF;
  RAISE NOTICE 'PASSOU T2: visita tecnica criada sem tecnico com login';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T3: conflito de horario e por profissional
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM schedule_appointment(
      'visit', v_request_b, v_customer, NULL,
      v_start + interval '30 minutes', v_start + interval '90 minutes',
      NULL, NULL, v_partner
    );
    RAISE EXCEPTION 'FALHOU T3: parceiro agendado em horario sobreposto';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T3: conflito avaliado por profissional';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T4: parceiro entra como segundo profissional
  -- ─────────────────────────────────────────────────────────────────────────
  PERFORM assign_technician(v_appointment, NULL, v_partner_2);

  SELECT COUNT(*) INTO v_count
  FROM appointment_assignments
  WHERE appointment_id = v_appointment AND revoked_at IS NULL;
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'FALHOU T4: esperado 2 profissionais, encontrado %', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T4: parceiro entra como segundo profissional';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T5: profissional inativo e recusado
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM assign_technician(v_appointment, NULL, v_inactive);
    RAISE EXCEPTION 'FALHOU T5: profissional inativo foi aceito';
  EXCEPTION
    WHEN no_data_found THEN
      RAISE NOTICE 'PASSOU T5: profissional inativo recusado';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T6: cancelar libera o parceiro e devolve o item a fila
  -- ─────────────────────────────────────────────────────────────────────────
  PERFORM cancel_appointment(v_appointment, 'Parceiro indisponivel');

  SELECT COUNT(*) INTO v_count
  FROM appointment_assignments
  WHERE appointment_id = v_appointment AND revoked_at IS NULL;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FALHOU T6: assignments continuam ativos apos cancelar';
  END IF;

  v_other := schedule_appointment(
    'visit', v_request, v_customer, NULL,
    v_start, v_start + interval '1 hour', NULL, NULL, v_partner
  );
  RAISE NOTICE 'PASSOU T6: parceiro liberado e item reagendado';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T7: isolamento — beta nao agenda com profissional do alpha
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_BETA')::text, true);

  BEGIN
    PERFORM schedule_appointment(
      'visit', v_request_b, v_customer, NULL,
      v_start + interval '6 hours', v_start + interval '7 hours',
      NULL, NULL, v_partner
    );
    RAISE EXCEPTION 'FALHOU T7: beta_owner agendou profissional do alpha';
  EXCEPTION
    WHEN no_data_found OR insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T7: beta_owner isolado dos profissionais do alpha';
  END;

  RAISE NOTICE '=== Testes F5-P4 (parceiro sem usuario) concluidos ===';
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

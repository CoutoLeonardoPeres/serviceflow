-- =============================================================================
-- Testes de isolamento RLS — migration 0051_appointment_events
--
-- Prova o contrato do F5-P1 (ADR-027):
--   * agendar registra evento 'scheduled' com o tecnico atribuido;
--   * ordem de servico agora pode ser agendada (era bloqueada pela FK e pelo
--     "ainda nao suportado no MVP" do schedule_appointment);
--   * o mesmo item nao pode ser agendado duas vezes enquanto estiver ativo;
--   * cancelar registra evento 'cancelled' com motivo e libera o tecnico,
--     devolvendo o item para a fila;
--   * o tecnico atribuido cancela mesmo sem appointments.write;
--   * appointment_events e append-only para authenticated;
--   * isolamento entre tenants.
--
-- Como executar:
--   psql $DATABASE_URL -f test/isolation/0024_appointment_events_test.sql
-- Substitua os \set abaixo pelos UUIDs reais do seed antes de executar.
-- ATENCAO (0053): schedule_appointment resolve o profissional a partir de
-- p_technician_user_id quando p_professional_id vem nulo. Estes testes usam a
-- forma antiga, entao exigem que exista `service_professionals` ativo com
-- `linked_user_id` apontando para cada usuario tecnico usado aqui.
-- =============================================================================

\set ON_ERROR_STOP on

\set TENANT_ALPHA  'a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1'
\set USER_ALPHA    'a1000000-0000-4000-8000-000000000001'
\set USER_BETA     'b2000000-0000-4000-8000-000000000002'
\set USER_TECH     'a1000000-0000-4000-8000-000000000003'

DO $$
DECLARE
  v_customer      uuid;
  v_request       uuid;
  v_work_order    uuid;
  v_appointment   uuid;
  v_wo_appointment uuid;
  v_start         timestamptz := date_trunc('hour', now()) + interval '1 day';
  v_technician    uuid;
  v_count         int;
  v_reason        text;
BEGIN
  RAISE NOTICE '=== F5-P1 Rastreabilidade da agenda — Inicio ===';

  -- SETUP
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  INSERT INTO customers (tenant_id, type, name, document)
  VALUES (:'TENANT_ALPHA', 'person', 'Cliente Agenda Teste', '52998224725')
  RETURNING id INTO v_customer;

  INSERT INTO service_requests (
    tenant_id, customer_id, title, description, channel, status
  )
  VALUES (
    :'TENANT_ALPHA', v_customer, 'Chamado agenda teste',
    'Descricao do chamado de teste da agenda.', 'whatsapp', 'opened'
  )
  RETURNING id INTO v_request;

  INSERT INTO work_orders (
    tenant_id, customer_id, request_id, title, description, status
  )
  VALUES (
    :'TENANT_ALPHA', v_customer, v_request, 'OS agenda teste',
    'Descricao da OS de teste da agenda.', 'open'
  )
  RETURNING id INTO v_work_order;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T1: agendar chamado grava evento 'scheduled' com o tecnico
  -- ─────────────────────────────────────────────────────────────────────────
  v_appointment := schedule_appointment(
    'visit', v_request, v_customer, NULL,
    v_start, v_start + interval '30 minutes', :'USER_TECH', NULL
  );

  SELECT technician_user_id INTO v_technician
  FROM appointment_events
  WHERE appointment_id = v_appointment AND event_type = 'scheduled';

  IF v_technician IS DISTINCT FROM :'USER_TECH'::uuid THEN
    RAISE EXCEPTION 'FALHOU T1: evento scheduled sem o tecnico atribuido (%)', v_technician;
  END IF;
  RAISE NOTICE 'PASSOU T1: evento scheduled registrado com o tecnico';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T2: o mesmo chamado nao pode ser agendado de novo enquanto ativo
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM schedule_appointment(
      'visit', v_request, v_customer, NULL,
      v_start + interval '2 hours', v_start + interval '2 hours 30 minutes',
      :'USER_TECH', NULL
    );
    RAISE EXCEPTION 'FALHOU T2: item agendado duas vezes';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T2: item ja agendado nao entra na fila de novo';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T3: cancelar grava motivo, libera o tecnico e devolve o item a fila
  -- ─────────────────────────────────────────────────────────────────────────
  PERFORM cancel_appointment(v_appointment, 'Cliente remarcou');

  SELECT reason INTO v_reason
  FROM appointment_events
  WHERE appointment_id = v_appointment AND event_type = 'cancelled';

  IF v_reason IS DISTINCT FROM 'Cliente remarcou' THEN
    RAISE EXCEPTION 'FALHOU T3: motivo do cancelamento nao registrado (%)', v_reason;
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM appointment_assignments
  WHERE appointment_id = v_appointment AND revoked_at IS NULL;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FALHOU T3: tecnico continua atribuido apos o cancelamento';
  END IF;
  RAISE NOTICE 'PASSOU T3: cancelamento registra motivo e libera o tecnico';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T4: item cancelado volta para a fila (pode ser reagendado)
  -- ─────────────────────────────────────────────────────────────────────────
  v_appointment := schedule_appointment(
    'visit', v_request, v_customer, NULL,
    v_start, v_start + interval '30 minutes', :'USER_TECH', NULL
  );
  RAISE NOTICE 'PASSOU T4: item cancelado foi reagendado';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T5: ordem de servico agora pode ser agendada
  -- ─────────────────────────────────────────────────────────────────────────
  v_wo_appointment := schedule_appointment(
    'work_order', v_work_order, v_customer, NULL,
    v_start + interval '3 hours', v_start + interval '4 hours',
    :'USER_TECH', NULL
  );

  SELECT COUNT(*) INTO v_count
  FROM appointment_events
  WHERE appointment_id = v_wo_appointment
    AND event_type = 'scheduled'
    AND kind = 'work_order';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FALHOU T5: agendamento de OS nao gerou evento';
  END IF;
  RAISE NOTICE 'PASSOU T5: ordem de servico agendada e registrada';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T6: appointment_events e append-only para authenticated
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    UPDATE appointment_events
    SET reason = 'adulterado'
    WHERE appointment_id = v_wo_appointment;
    -- Sem policy de UPDATE, o comando nao atinge nenhuma linha em vez de
    -- estourar erro. Zero linhas afetadas e o resultado esperado.
    GET DIAGNOSTICS v_count = ROW_COUNT;
    IF v_count > 0 THEN
      RAISE EXCEPTION 'FALHOU T6: historico da agenda foi alterado';
    END IF;
    RAISE NOTICE 'PASSOU T6: historico e append-only';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T6: historico e append-only (privilegio negado)';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T7: tecnico atribuido cancela o proprio atendimento
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_TECH')::text, true);

  PERFORM cancel_appointment(v_wo_appointment, 'Cancelado em campo');

  SELECT COUNT(*) INTO v_count
  FROM appointment_events
  WHERE appointment_id = v_wo_appointment AND event_type = 'cancelled';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FALHOU T7: tecnico de campo nao conseguiu cancelar';
  END IF;
  RAISE NOTICE 'PASSOU T7: tecnico de campo cancela o proprio atendimento';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T8: isolamento — beta nao ve os eventos do alpha
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_BETA')::text, true);

  SELECT COUNT(*) INTO v_count
  FROM appointment_events
  WHERE tenant_id = :'TENANT_ALPHA';
  IF v_count > 0 THEN
    RAISE EXCEPTION 'FALHOU T8: beta_owner viu % eventos do tenant alpha', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T8: beta_owner isolado do historico do alpha';

  RAISE NOTICE '=== Testes F5-P1 (rastreabilidade da agenda) concluidos ===';
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

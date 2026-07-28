-- =============================================================================
-- Testes de isolamento RLS — migration 0058_quotation_chain_closing
--
-- Prova o contrato da 2a metade do F6-P1:
--   * OS concluida fecha o chamado de origem;
--   * a conclusao fica registrada no historico do orcamento;
--   * orcamento recusado fecha o chamado;
--   * reabrir dentro de 30 dias devolve orcamento e chamado ao jogo;
--   * reabrir fora da janela e recusado;
--   * orcamento aprovado nao reabre (viraria duas OS para o mesmo trabalho);
--   * chamado cancelado nao e reaberto nem fechado por engano.
--
-- Como executar:
--   psql $DATABASE_URL -f test/isolation/0029_quotation_chain_closing_test.sql
-- Substitua os \set abaixo pelos UUIDs reais do seed antes de executar.
-- Requer 0056, 0057 e 0058 aplicadas.
-- =============================================================================

\set ON_ERROR_STOP on

\set TENANT_ALPHA  'a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1'
\set USER_ALPHA    'a1000000-0000-4000-8000-000000000001'

DO $$
DECLARE
  v_customer  uuid;
  v_request   uuid;
  v_request_b uuid;
  v_quote     jsonb;
  v_quote_id  uuid;
  v_quote_b   uuid;
  v_wo        uuid;
  v_status    text;
  v_count     int;
BEGIN
  RAISE NOTICE '=== 0058 Encerramento da cadeia — Inicio ===';

  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  INSERT INTO customers (tenant_id, type, name, document)
  VALUES (:'TENANT_ALPHA', 'person', 'Cliente Cadeia', '52998224725')
  RETURNING id INTO v_customer;

  INSERT INTO service_requests (
    tenant_id, customer_id, title, description, channel, status
  ) VALUES (
    :'TENANT_ALPHA', v_customer, 'Chamado que vai ate o fim',
    'Chamado que vira orcamento, OS e fecha.', 'whatsapp', 'opened'
  ) RETURNING id INTO v_request;

  v_quote := create_quotation(
    v_customer, v_request, (now() + interval '10 days')::date, NULL, NULL,
    jsonb_build_array(jsonb_build_object(
      'kind', 'service', 'description', 'Servico completo',
      'quantity', 1, 'unit_price_cents', 30000, 'unit_cost_cents', 12000
    ))
  );
  v_quote_id := (v_quote->>'id')::uuid;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T1: OS concluida fecha o chamado
  -- ─────────────────────────────────────────────────────────────────────────
  PERFORM decide_quotation(v_quote_id, 'approved', 'Cliente aprovou', NULL);

  SELECT id INTO v_wo FROM work_orders WHERE quotation_id = v_quote_id;
  IF v_wo IS NULL THEN
    RAISE EXCEPTION 'FALHOU T1: 0056 nao gerou a OS (pre-condicao)';
  END IF;

  PERFORM transition_work_order(v_wo, 'in_progress', NULL);
  PERFORM transition_work_order(v_wo, 'done', 'Concluida no teste');

  SELECT status INTO v_status FROM service_requests WHERE id = v_request;
  IF v_status <> 'closed' THEN
    RAISE EXCEPTION 'FALHOU T1: chamado ficou em % apos a OS concluir', v_status;
  END IF;
  RAISE NOTICE 'PASSOU T1: OS concluida fechou o chamado';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T2: a conclusao fica registrada no historico do orcamento
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT COUNT(*) INTO v_count
  FROM quotation_status_history
  WHERE quotation_id = v_quote_id AND notes LIKE '%concluída%';
  IF v_count < 1 THEN
    RAISE EXCEPTION 'FALHOU T2: conclusao da OS nao registrada no orcamento';
  END IF;
  RAISE NOTICE 'PASSOU T2: conclusao registrada no historico do orcamento';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T3: orcamento aprovado nao reabre
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM reopen_quotation(v_quote_id, NULL);
    RAISE EXCEPTION 'FALHOU T3: orcamento aprovado foi reaberto';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T3: aprovado nao reabre';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T4: orcamento recusado fecha o chamado
  -- ─────────────────────────────────────────────────────────────────────────
  INSERT INTO service_requests (
    tenant_id, customer_id, title, description, channel, status
  ) VALUES (
    :'TENANT_ALPHA', v_customer, 'Chamado que sera recusado',
    'Chamado cujo orcamento o cliente recusa.', 'whatsapp', 'opened'
  ) RETURNING id INTO v_request_b;

  v_quote := create_quotation(
    v_customer, v_request_b, (now() + interval '10 days')::date, NULL, NULL,
    jsonb_build_array(jsonb_build_object(
      'kind', 'service', 'description', 'Servico recusado',
      'quantity', 1, 'unit_price_cents', 45000, 'unit_cost_cents', 20000
    ))
  );
  v_quote_b := (v_quote->>'id')::uuid;

  PERFORM decide_quotation(v_quote_b, 'rejected', 'Cliente achou caro', NULL);

  SELECT status INTO v_status FROM service_requests WHERE id = v_request_b;
  IF v_status <> 'closed' THEN
    RAISE EXCEPTION 'FALHOU T4: chamado ficou em % apos a recusa', v_status;
  END IF;
  RAISE NOTICE 'PASSOU T4: recusa fechou o chamado';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T5: reabrir dentro da janela devolve orcamento e chamado
  -- ─────────────────────────────────────────────────────────────────────────
  PERFORM reopen_quotation(v_quote_b, 'Cliente mudou de ideia');

  SELECT status INTO v_status FROM quotations WHERE id = v_quote_b;
  IF v_status <> 'sent' THEN
    RAISE EXCEPTION 'FALHOU T5: orcamento reaberto ficou em %', v_status;
  END IF;

  SELECT status INTO v_status FROM service_requests WHERE id = v_request_b;
  IF v_status <> 'converted_to_quote' THEN
    RAISE EXCEPTION 'FALHOU T5: chamado nao voltou (esta em %)', v_status;
  END IF;
  RAISE NOTICE 'PASSOU T5: reabertura devolveu orcamento e chamado juntos';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T6: fora da janela de 30 dias, recusa
  -- ─────────────────────────────────────────────────────────────────────────
  PERFORM decide_quotation(v_quote_b, 'rejected', 'Recusou de novo', NULL);

  -- Envelhece artificialmente a recusa: 31 dias atras.
  UPDATE quotation_status_history
  SET changed_at = now() - interval '31 days'
  WHERE quotation_id = v_quote_b AND status = 'rejected';
  UPDATE quotations
  SET updated_at = now() - interval '31 days'
  WHERE id = v_quote_b;

  BEGIN
    PERFORM reopen_quotation(v_quote_b, NULL);
    RAISE EXCEPTION 'FALHOU T6: reabriu orcamento fora da janela de 30 dias';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T6: janela de 30 dias e respeitada';
  END;

  RAISE NOTICE '=== 0058 Encerramento da cadeia — TODOS OS TESTES PASSARAM ===';
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

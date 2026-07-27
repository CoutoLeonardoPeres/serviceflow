-- =============================================================================
-- Testes de isolamento RLS — migration 0040_message_templates
--
-- Cobre message_templates e communication_logs: isolamento entre tenants,
-- exigencia de customers.write para escrita, e imutabilidade dos logs
-- (nao ha policy de UPDATE nem DELETE em communication_logs).
--
-- Como executar:
--   psql $DATABASE_URL -f test/isolation/0015_communications_test.sql
-- Substitua os \set abaixo pelos UUIDs reais do seed antes de executar.
-- =============================================================================

\set ON_ERROR_STOP on

\set TENANT_ALPHA  'a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1'
\set USER_ALPHA    'a1000000-0000-4000-8000-000000000001'
\set USER_BETA     'b2000000-0000-4000-8000-000000000002'
\set USER_VIEWER   'a1000000-0000-4000-8000-000000000004'

DO $$
DECLARE
  v_customer_alpha uuid;
  v_template_id    uuid;
  v_log_id         uuid;
  v_count          int;
BEGIN
  RAISE NOTICE '=== F2 RLS Comunicacoes — Inicio ===';

  -- SETUP
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);
  INSERT INTO customers (tenant_id, type, name, phone, is_active)
  VALUES (:'TENANT_ALPHA', 'company', 'Cliente Comunicacao Alpha', '11999990000', true)
  RETURNING id INTO v_customer_alpha;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T1: owner cria template
  -- ─────────────────────────────────────────────────────────────────────────
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  INSERT INTO message_templates (tenant_id, name, channel, body)
  VALUES (:'TENANT_ALPHA', 'Template Teste Alpha', 'whatsapp',
          'Ola, {{customer_name}}! Mensagem de teste. — {{company_name}}')
  RETURNING id INTO v_template_id;
  RAISE NOTICE 'PASSOU T1: owner criou template (id=%)', v_template_id;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T2: viewer (sem customers.write) NAO cria template
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_VIEWER')::text, true);

  BEGIN
    INSERT INTO message_templates (tenant_id, name, channel, body)
    VALUES (:'TENANT_ALPHA', 'Template do Viewer', 'whatsapp', 'nao deveria entrar');
    RAISE EXCEPTION 'FALHOU T2: viewer sem customers.write criou template';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T2: viewer sem customers.write nao cria template';
  END;

  -- Viewer tem customers.read, entao DEVE conseguir ler os templates do tenant
  SELECT COUNT(*) INTO v_count FROM message_templates WHERE id = v_template_id;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FALHOU T2b: viewer com customers.read nao leu template (count=%)', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T2b: viewer com customers.read le templates do proprio tenant';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T3: isolamento — beta nao ve template do alpha
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_BETA')::text, true);

  SELECT COUNT(*) INTO v_count FROM message_templates WHERE id = v_template_id;
  IF v_count > 0 THEN
    RAISE EXCEPTION 'FALHOU T3: beta_owner viu template do tenant alpha';
  END IF;
  RAISE NOTICE 'PASSOU T3: beta_owner nao ve template do tenant alpha';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T4: isolamento — beta nao altera nem apaga template do alpha
  -- ─────────────────────────────────────────────────────────────────────────
  UPDATE message_templates SET name = 'Sequestrado' WHERE id = v_template_id;
  IF FOUND THEN
    RAISE EXCEPTION 'FALHOU T4: beta_owner alterou template do tenant alpha';
  END IF;

  DELETE FROM message_templates WHERE id = v_template_id;
  IF FOUND THEN
    RAISE EXCEPTION 'FALHOU T4: beta_owner apagou template do tenant alpha';
  END IF;
  RAISE NOTICE 'PASSOU T4: beta_owner nao altera nem apaga template do alpha';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T5: log_communication deriva tenant do cliente e registra
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  SELECT log_communication(
    v_customer_alpha, 'whatsapp', 'Ola, mensagem de teste', NULL,
    NULL, NULL, v_template_id, 'sent'
  ) INTO v_log_id;

  SELECT COUNT(*) INTO v_count
  FROM communication_logs
  WHERE id = v_log_id AND tenant_id = :'TENANT_ALPHA';
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FALHOU T5: log de comunicacao nao registrado no tenant correto';
  END IF;
  RAISE NOTICE 'PASSOU T5: comunicacao registrada com tenant derivado do cliente';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T6: communication_logs e imutavel (sem policy de UPDATE/DELETE)
  -- ─────────────────────────────────────────────────────────────────────────
  UPDATE communication_logs SET body_preview = 'adulterado' WHERE id = v_log_id;
  IF FOUND THEN
    RAISE EXCEPTION 'FALHOU T6: log de comunicacao foi alterado (deveria ser imutavel)';
  END IF;

  DELETE FROM communication_logs WHERE id = v_log_id;
  IF FOUND THEN
    RAISE EXCEPTION 'FALHOU T6: log de comunicacao foi apagado (deveria ser imutavel)';
  END IF;
  RAISE NOTICE 'PASSOU T6: communication_logs e imutavel mesmo para o owner';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T7: isolamento — beta nao ve log de comunicacao do alpha
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_BETA')::text, true);

  SELECT COUNT(*) INTO v_count FROM communication_logs WHERE id = v_log_id;
  IF v_count > 0 THEN
    RAISE EXCEPTION 'FALHOU T7: beta_owner viu log de comunicacao do tenant alpha';
  END IF;
  RAISE NOTICE 'PASSOU T7: beta_owner nao ve communication_logs do alpha';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T8: beta nao registra comunicacao para cliente do alpha
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM log_communication(
      v_customer_alpha, 'whatsapp', 'tentativa cross tenant', NULL,
      NULL, NULL, NULL, 'sent'
    );
    RAISE EXCEPTION 'FALHOU T8: beta_owner registrou comunicacao para cliente do alpha';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T8: beta_owner nao registra comunicacao para cliente do alpha';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T9: auditoria — comunicacao gerou audit_log
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SELECT COUNT(*) INTO v_count
  FROM audit_logs
  WHERE action = 'communication.sent' AND tenant_id = :'TENANT_ALPHA';

  IF v_count < 1 THEN
    RAISE EXCEPTION 'FALHOU T9: comunicacao nao gerou audit_log (count=%)', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T9: % evento(s) de auditoria de comunicacao', v_count;

  RAISE NOTICE '=== Testes F2 (comunicacoes) concluidos ===';
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

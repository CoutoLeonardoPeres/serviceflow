-- =============================================================================
-- Testes de isolamento RLS — migration 0041_satisfaction_public_survey
--
-- Este e o teste mais sensivel da suite: valida o UNICO caminho de escrita
-- anonima criado no F2 (submit_public_satisfaction).
--
-- O que precisa ficar provado aqui:
--   * token invalido, expirado ou revogado nao escreve nada;
--   * o token define tenant e OS — nada de identificacao vem do chamador;
--   * a leitura publica nao vaza dado de cliente;
--   * quem nao e do tenant nao emite nem enxerga links.
--
-- Como executar:
--   psql $DATABASE_URL -f test/isolation/0016_satisfaction_public_link_test.sql
-- Substitua os \set abaixo pelos UUIDs reais do seed antes de executar.
-- =============================================================================

\set ON_ERROR_STOP on

\set TENANT_ALPHA  'a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1'
\set USER_ALPHA    'a1000000-0000-4000-8000-000000000001'
\set USER_BETA     'b2000000-0000-4000-8000-000000000002'
\set USER_TECH     'a1000000-0000-4000-8000-000000000003'
\set USER_VIEWER   'a1000000-0000-4000-8000-000000000004'

DO $$
DECLARE
  v_customer_alpha uuid;
  v_request_alpha  uuid;
  v_quote          jsonb;
  v_quotation_id   uuid;
  v_wo             jsonb;
  v_wo_id          uuid;
  v_token          text;
  v_token2         text;
  v_ctx            jsonb;
  v_count          int;
  v_rating         int;
  v_link_id        uuid;
BEGIN
  RAISE NOTICE '=== F2 RLS Pesquisa Publica de Satisfacao — Inicio ===';

  -- SETUP: cliente com dados sensiveis, para provar que nao vazam
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);
  INSERT INTO customers (tenant_id, type, name, phone, email, is_active)
  VALUES (:'TENANT_ALPHA', 'company', 'Cliente Pesquisa Alpha',
          '11988887777', 'sigiloso@exemplo.com', true)
  RETURNING id INTO v_customer_alpha;

  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);
  INSERT INTO service_requests (
    tenant_id, number, customer_id, title, description, channel, status
  ) VALUES (
    :'TENANT_ALPHA', 9921, v_customer_alpha, 'Chamado Pesquisa Alpha',
    'Descricao suficiente para teste de pesquisa publica.', 'phone', 'opened'
  ) RETURNING id INTO v_request_alpha;

  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  SELECT create_quotation(
    v_customer_alpha, v_request_alpha, '2026-08-20', 'teste pesquisa', NULL,
    '[{"kind":"service","description":"Servico","quantity":1,"unit_price_cents":250000,"unit_cost_cents":90000}]'::jsonb
  ) INTO v_quote;
  v_quotation_id := (v_quote->>'id')::uuid;

  RESET role;
  UPDATE quotations SET status = 'approved' WHERE id = v_quotation_id;

  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);
  SELECT convert_approved_quotation_to_work_order(v_quotation_id) INTO v_wo;
  v_wo_id := (v_wo->>'id')::uuid;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T1: OS nao concluida nao gera link de pesquisa
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM create_satisfaction_public_link(v_wo_id, NULL);
    RAISE EXCEPTION 'FALHOU T1: link gerado para OS nao concluida';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T1: link bloqueado para OS nao concluida';
  END;

  PERFORM transition_work_order(v_wo_id, 'done', 'concluida para teste de pesquisa');

  -- ─────────────────────────────────────────────────────────────────────────
  -- T2: viewer (sem work_orders.execute/manage) nao gera link
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_VIEWER')::text, true);

  BEGIN
    PERFORM create_satisfaction_public_link(v_wo_id, NULL);
    RAISE EXCEPTION 'FALHOU T2: viewer sem permissao gerou link de pesquisa';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T2: viewer sem permissao nao gera link';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T3: beta nao gera link para OS do alpha
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_BETA')::text, true);

  BEGIN
    PERFORM create_satisfaction_public_link(v_wo_id, NULL);
    RAISE EXCEPTION 'FALHOU T3: beta_owner gerou link para OS do tenant alpha';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T3: beta_owner nao gera link para OS do alpha';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T4: tecnico (work_orders.execute) gera link com sucesso
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_TECH')::text, true);

  SELECT create_satisfaction_public_link(v_wo_id, NULL) INTO v_token;
  IF v_token IS NULL OR length(v_token) <> 64 THEN
    RAISE EXCEPTION 'FALHOU T4: token ausente ou com tamanho inesperado (len=%)',
      COALESCE(length(v_token), -1);
  END IF;
  RAISE NOTICE 'PASSOU T4: tecnico gerou link (token de 32 bytes em hex)';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T5: o token em claro NAO fica no banco — apenas o hash
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SELECT COUNT(*) INTO v_count
  FROM satisfaction_public_links
  WHERE token_hash = v_token;
  IF v_count > 0 THEN
    RAISE EXCEPTION 'FALHOU T5: token em claro armazenado no banco';
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM satisfaction_public_links
  WHERE token_hash = encode(extensions.digest(v_token, 'sha256'), 'hex');
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FALHOU T5: hash do token nao encontrado (count=%)', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T5: banco guarda apenas o SHA-256 do token';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T6: contexto publico (ANONIMO) devolve dados minimos, sem vazar cliente
  -- ─────────────────────────────────────────────────────────────────────────
  SET LOCAL role = anon;
  PERFORM set_config('request.jwt.claims', 'null', true); -- limpa claim residual de SET LOCAL anterior
  SELECT get_public_satisfaction_context(v_token) INTO v_ctx;

  IF v_ctx->>'service_title' IS NULL OR v_ctx->>'company_name' IS NULL THEN
    RAISE EXCEPTION 'FALHOU T6: contexto publico incompleto';
  END IF;

  -- Nenhuma chave de dado sensivel pode aparecer no retorno
  IF v_ctx ? 'customer_name'   OR v_ctx ? 'customer_id'
     OR v_ctx ? 'phone'        OR v_ctx ? 'email'
     OR v_ctx ? 'total_cents'  OR v_ctx ? 'address' THEN
    RAISE EXCEPTION 'FALHOU T6: contexto publico vazou dado sensivel: %', v_ctx;
  END IF;

  -- E o conteudo textual nao pode conter os dados do cliente
  IF v_ctx::text LIKE '%11988887777%' OR v_ctx::text LIKE '%sigiloso@exemplo.com%' THEN
    RAISE EXCEPTION 'FALHOU T6: telefone/e-mail do cliente vazou no contexto publico';
  END IF;
  RAISE NOTICE 'PASSOU T6: contexto publico traz apenas dados minimos';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T7: token invalido nao le nem escreve
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM get_public_satisfaction_context('token-que-nao-existe');
    RAISE EXCEPTION 'FALHOU T7: contexto retornado para token invalido';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T7a: token invalido nao retorna contexto';
  END;

  BEGIN
    PERFORM submit_public_satisfaction('token-que-nao-existe', 5, 'Invasor', 'nada');
    RAISE EXCEPTION 'FALHOU T7: resposta aceita com token invalido';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T7b: token invalido nao registra resposta';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T8: nota fora de 1..5 e rejeitada no caminho anonimo
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM submit_public_satisfaction(v_token, 9, 'Cliente', 'nota invalida');
    RAISE EXCEPTION 'FALHOU T8: nota fora do intervalo aceita no caminho anonimo';
  EXCEPTION
    WHEN check_violation THEN
      RAISE NOTICE 'PASSOU T8: nota fora do intervalo rejeitada';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T9: resposta anonima valida grava no tenant e OS corretos
  -- ─────────────────────────────────────────────────────────────────────────
  PERFORM submit_public_satisfaction(v_token, 5, 'Cliente Final', 'Muito bom.');

  RESET role;
  SELECT COUNT(*) INTO v_count
  FROM work_order_satisfaction
  WHERE work_order_id = v_wo_id
    AND tenant_id = :'TENANT_ALPHA'
    AND customer_id = v_customer_alpha;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FALHOU T9: resposta anonima nao gravou no tenant/OS corretos (count=%)', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T9: resposta anonima gravada com tenant e OS derivados do token';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T10: correcao da resposta faz upsert, nao duplica
  -- ─────────────────────────────────────────────────────────────────────────
  SET LOCAL role = anon;
  PERFORM set_config('request.jwt.claims', 'null', true); -- limpa claim residual de SET LOCAL anterior
  PERFORM submit_public_satisfaction(v_token, 2, 'Cliente Final', 'Revisando.');

  RESET role;
  SELECT COUNT(*) INTO v_count FROM work_order_satisfaction WHERE work_order_id = v_wo_id;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FALHOU T10: resposta duplicada em vez de atualizada (count=%)', v_count;
  END IF;

  SELECT rating INTO v_rating FROM work_order_satisfaction WHERE work_order_id = v_wo_id;
  IF v_rating <> 2 THEN
    RAISE EXCEPTION 'FALHOU T10: resposta nao foi atualizada (rating=%)', v_rating;
  END IF;
  RAISE NOTICE 'PASSOU T10: segunda resposta atualizou a existente (upsert)';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T11: gerar novo link revoga o anterior; token antigo para de funcionar
  -- ─────────────────────────────────────────────────────────────────────────
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_TECH')::text, true);
  SELECT create_satisfaction_public_link(v_wo_id, NULL) INTO v_token2;

  SET LOCAL role = anon;
  PERFORM set_config('request.jwt.claims', 'null', true); -- limpa claim residual de SET LOCAL anterior
  BEGIN
    PERFORM get_public_satisfaction_context(v_token);
    RAISE EXCEPTION 'FALHOU T11: token antigo continuou valido apos novo link';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T11: token antigo revogado ao gerar novo link';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T12: link expirado nao funciona
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  UPDATE satisfaction_public_links
  SET expires_at = now() - interval '1 day'
  WHERE token_hash = encode(extensions.digest(v_token2, 'sha256'), 'hex');

  SET LOCAL role = anon;
  PERFORM set_config('request.jwt.claims', 'null', true); -- limpa claim residual de SET LOCAL anterior
  BEGIN
    PERFORM submit_public_satisfaction(v_token2, 4, 'Cliente', 'fora do prazo');
    RAISE EXCEPTION 'FALHOU T12: resposta aceita com link expirado';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T12: link expirado nao aceita resposta';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T13: link revogado manualmente nao funciona
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  UPDATE satisfaction_public_links
  SET expires_at = now() + interval '30 days'
  WHERE token_hash = encode(extensions.digest(v_token2, 'sha256'), 'hex');

  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_TECH')::text, true);
  PERFORM revoke_satisfaction_public_link(v_wo_id);

  SET LOCAL role = anon;
  PERFORM set_config('request.jwt.claims', 'null', true); -- limpa claim residual de SET LOCAL anterior
  BEGIN
    PERFORM submit_public_satisfaction(v_token2, 4, 'Cliente', 'apos revogacao');
    RAISE EXCEPTION 'FALHOU T13: resposta aceita com link revogado';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T13: link revogado nao aceita resposta';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T14: anon nao le a tabela de links diretamente (so via RPC)
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT COUNT(*) INTO v_count FROM satisfaction_public_links;
  IF v_count > 0 THEN
    RAISE EXCEPTION 'FALHOU T14: anon leu satisfaction_public_links diretamente (count=%)', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T14: anon nao le satisfaction_public_links diretamente';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T15: isolamento — beta nao ve links do alpha
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_BETA')::text, true);

  SELECT COUNT(*) INTO v_count FROM satisfaction_public_links;
  IF v_count > 0 THEN
    RAISE EXCEPTION 'FALHOU T15: beta_owner viu links de pesquisa do tenant alpha';
  END IF;
  RAISE NOTICE 'PASSOU T15: beta_owner nao ve satisfaction_public_links do alpha';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T16: auditoria — emissao e resposta publica geraram audit_log
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SELECT COUNT(*) INTO v_count
  FROM audit_logs
  WHERE action = 'work_order.satisfaction_link.created'
    AND tenant_id = :'TENANT_ALPHA';
  IF v_count < 1 THEN
    RAISE EXCEPTION 'FALHOU T16: emissao de link nao gerou audit_log';
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM audit_logs
  WHERE action = 'work_order.satisfaction.public_submitted'
    AND tenant_id = :'TENANT_ALPHA';
  IF v_count < 1 THEN
    RAISE EXCEPTION 'FALHOU T16: resposta publica nao gerou audit_log';
  END IF;
  RAISE NOTICE 'PASSOU T16: emissao e resposta publica auditadas';

  RAISE NOTICE '=== Testes F2 (pesquisa publica) concluidos ===';
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

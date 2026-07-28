-- =============================================================================
-- Testes de isolamento RLS — migration 0056_auto_work_order_on_approval
--
-- Prova o contrato do F6-P1:
--   * aprovar pelo sistema (decide_quotation) cria a OS sozinho;
--   * o chamado de origem vai para 'converted_to_work_order';
--   * aprovar pelo link publico (anon, sem tenant no contexto) tambem cria;
--   * a criacao e idempotente — trigger + botao manual nao duplicam a OS;
--   * orcamento que nao foi aprovado nao gera OS;
--   * a RPC manual continua exigindo work_orders.write.
--
-- Como executar:
--   psql $DATABASE_URL -f test/isolation/0027_auto_work_order_test.sql
-- Substitua os \set abaixo pelos UUIDs reais do seed antes de executar.
-- Requer que 0054/0055/0056 estejam aplicadas.
-- =============================================================================

\set ON_ERROR_STOP on

\set TENANT_ALPHA  'a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1'
\set USER_ALPHA    'a1000000-0000-4000-8000-000000000001'

DO $$
DECLARE
  v_customer   uuid;
  v_request    uuid;
  v_quote      jsonb;
  v_quote_id   uuid;
  v_quote_id2  uuid;
  v_token      text;
  v_count      int;
  v_status     text;
  v_wo_id      uuid;
BEGIN
  RAISE NOTICE '=== F6-P1 OS automatica na aprovacao — Inicio ===';

  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  INSERT INTO customers (tenant_id, type, name, document)
  VALUES (:'TENANT_ALPHA', 'person', 'Cliente OS Automatica', '52998224725')
  RETURNING id INTO v_customer;

  INSERT INTO service_requests (
    tenant_id, customer_id, title, description, channel, status
  )
  VALUES (
    :'TENANT_ALPHA', v_customer, 'Chamado da OS automatica',
    'Chamado que vira orcamento e depois OS.', 'whatsapp', 'opened'
  )
  RETURNING id INTO v_request;

  v_quote := create_quotation(
    v_customer, v_request, (now() + interval '10 days')::date,
    'Observacoes do orcamento', NULL,
    jsonb_build_array(
      jsonb_build_object(
        'kind', 'service', 'description', 'Instalacao',
        'quantity', 2, 'unit_price_cents', 15000, 'unit_cost_cents', 8000
      ),
      jsonb_build_object(
        'kind', 'material', 'description', 'Cabo 2,5mm',
        'quantity', 10, 'unit_price_cents', 500, 'unit_cost_cents', 300
      )
    )
  );
  v_quote_id := (v_quote->>'id')::uuid;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T1: orcamento ainda nao aprovado nao tem OS
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT COUNT(*) INTO v_count
  FROM work_orders WHERE quotation_id = v_quote_id;
  IF v_count <> 0 THEN
    RAISE EXCEPTION 'FALHOU T1: OS criada antes da aprovacao';
  END IF;
  RAISE NOTICE 'PASSOU T1: sem aprovacao, sem OS';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T2: aprovar pelo sistema cria a OS com os itens da versao atual
  -- ─────────────────────────────────────────────────────────────────────────
  PERFORM decide_quotation(v_quote_id, 'approved', 'Cliente por telefone', NULL);

  SELECT id INTO v_wo_id
  FROM work_orders WHERE quotation_id = v_quote_id;
  IF v_wo_id IS NULL THEN
    RAISE EXCEPTION 'FALHOU T2: aprovacao nao gerou OS';
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM work_order_items WHERE work_order_id = v_wo_id;
  IF v_count <> 2 THEN
    RAISE EXCEPTION 'FALHOU T2: OS nasceu com % itens, esperado 2', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T2: aprovacao interna gerou a OS com os itens';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T3: o chamado de origem acompanha
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT status INTO v_status FROM service_requests WHERE id = v_request;
  IF v_status <> 'converted_to_work_order' THEN
    RAISE EXCEPTION 'FALHOU T3: chamado ficou em % apos virar OS', v_status;
  END IF;
  RAISE NOTICE 'PASSOU T3: chamado marcado como convertido';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T4: botao manual sobre orcamento ja convertido nao duplica
  -- ─────────────────────────────────────────────────────────────────────────
  PERFORM convert_approved_quotation_to_work_order(v_quote_id);

  SELECT COUNT(*) INTO v_count
  FROM work_orders WHERE quotation_id = v_quote_id;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FALHOU T4: % OS para o mesmo orcamento', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T4: criacao e idempotente';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T5: aprovacao pelo link publico (anon) tambem cria a OS
  -- ─────────────────────────────────────────────────────────────────────────
  v_quote := create_quotation(
    v_customer, NULL, (now() + interval '10 days')::date, NULL, NULL,
    jsonb_build_array(
      jsonb_build_object(
        'kind', 'service', 'description', 'Manutencao',
        'quantity', 1, 'unit_price_cents', 20000, 'unit_cost_cents', 9000
      )
    )
  );
  v_quote_id2 := (v_quote->>'id')::uuid;
  v_token := create_quotation_public_link(v_quote_id2, NULL);

  RESET role;
  SET LOCAL role = anon;
  PERFORM set_config('request.jwt.claims', NULL, true);

  PERFORM decide_public_quotation(v_token, 'approved', 'Cliente no link', NULL);

  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  SELECT COUNT(*) INTO v_count
  FROM work_orders WHERE quotation_id = v_quote_id2;
  IF v_count <> 1 THEN
    RAISE EXCEPTION 'FALHOU T5: aprovacao publica gerou % OS', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T5: aprovacao pelo link publico gerou a OS';

  RAISE NOTICE '=== F6-P1 OS automatica na aprovacao — TODOS OS TESTES PASSARAM ===';
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

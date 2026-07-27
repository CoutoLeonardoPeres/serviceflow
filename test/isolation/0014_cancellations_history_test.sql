-- =============================================================================
-- Testes de isolamento RLS — migrations 0036_cancellations + 0039_permissions
--
-- Cobre a tabela quotation_status_history (0036) e, principalmente, atua como
-- TESTE DE REGRESSAO da falha corrigida em 0039:
--   antes de 0039, cancel_quotation e cancel_work_order verificavam apenas se o
--   usuario pertencia ao tenant, sem checar quotations.write / work_orders.manage.
--   Qualquer membro do tenant podia cancelar orcamentos e OS.
--
-- T3 e T4 abaixo falham se 0039 for revertida. Nao remova esses casos.
--
-- Como executar:
--   psql $DATABASE_URL -f test/isolation/0014_cancellations_history_test.sql
-- Substitua os \set abaixo pelos UUIDs reais do seed antes de executar.
-- =============================================================================

\set ON_ERROR_STOP on

\set TENANT_ALPHA  'a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1'
\set USER_ALPHA    'a1000000-0000-4000-8000-000000000001'
\set USER_BETA     'b2000000-0000-4000-8000-000000000002'
\set USER_TECH     'a1000000-0000-4000-8000-000000000003'

DO $$
DECLARE
  v_customer_alpha uuid;
  v_request_alpha  uuid;
  v_quote          jsonb;
  v_quotation_id   uuid;
  v_quote2         jsonb;
  v_quotation2_id  uuid;
  v_wo             jsonb;
  v_wo_id          uuid;
  v_count          int;
  v_reason         text;
BEGIN
  RAISE NOTICE '=== F2 RLS Cancelamentos + Historico — Inicio ===';

  -- SETUP
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);
  INSERT INTO customers (tenant_id, type, name, is_active)
  VALUES (:'TENANT_ALPHA', 'company', 'Cliente Cancelamento Alpha', true)
  RETURNING id INTO v_customer_alpha;

  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);
  INSERT INTO service_requests (
    tenant_id, number, customer_id, title, description, channel, status
  ) VALUES (
    :'TENANT_ALPHA', 9911, v_customer_alpha, 'Chamado Cancelamento Alpha',
    'Descricao suficiente para teste de cancelamento alpha.', 'phone', 'opened'
  ) RETURNING id INTO v_request_alpha;

  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);

  SELECT create_quotation(
    v_customer_alpha, v_request_alpha, '2026-08-20', 'teste cancelamento', NULL,
    '[{"kind":"service","description":"Servico","quantity":1,"unit_price_cents":20000,"unit_cost_cents":8000}]'::jsonb
  ) INTO v_quote;
  v_quotation_id := (v_quote->>'id')::uuid;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T1: owner cancela orcamento com motivo; historico e registrado
  -- ─────────────────────────────────────────────────────────────────────────
  PERFORM cancel_quotation(v_quotation_id, 'Cliente desistiu do servico.');

  SELECT cancellation_reason INTO v_reason FROM quotations WHERE id = v_quotation_id;
  IF v_reason IS DISTINCT FROM 'Cliente desistiu do servico.' THEN
    RAISE EXCEPTION 'FALHOU T1: motivo de cancelamento nao gravado (%)', v_reason;
  END IF;

  SELECT COUNT(*) INTO v_count
  FROM quotation_status_history
  WHERE quotation_id = v_quotation_id AND status = 'cancelled';
  IF v_count < 1 THEN
    RAISE EXCEPTION 'FALHOU T1: historico de cancelamento nao registrado';
  END IF;
  RAISE NOTICE 'PASSOU T1: orcamento cancelado com motivo e historico';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T2: cancelar orcamento ja cancelado e bloqueado
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM cancel_quotation(v_quotation_id, 'Segunda tentativa.');
    RAISE EXCEPTION 'FALHOU T2: orcamento cancelado foi cancelado de novo';
  EXCEPTION
    -- cancel_quotation levanta RAISE EXCEPTION genérico (ERRCODE 'P0001'),
    -- não um check_violation de constraint (SQLSTATE 23514) — mas nosso
    -- próprio 'FALHOU T2' acima também é P0001 por padrão, então precisa
    -- distinguir pela mensagem em vez de engolir qualquer P0001.
    WHEN SQLSTATE 'P0001' THEN
      IF SQLERRM LIKE 'FALHOU T2%' THEN
        RAISE;
      END IF;
      RAISE NOTICE 'PASSOU T2: cancelamento duplo bloqueado (%)', SQLERRM;
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T3: REGRESSAO 0039 — tecnico (sem quotations.write) NAO cancela orcamento
  -- ─────────────────────────────────────────────────────────────────────────
  SELECT create_quotation(
    v_customer_alpha, v_request_alpha, '2026-08-20', 'teste permissao', NULL,
    '[{"kind":"service","description":"Servico 2","quantity":1,"unit_price_cents":15000,"unit_cost_cents":5000}]'::jsonb
  ) INTO v_quote2;
  v_quotation2_id := (v_quote2->>'id')::uuid;

  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_TECH')::text, true);

  BEGIN
    PERFORM cancel_quotation(v_quotation2_id, 'Tecnico tentando cancelar.');
    RAISE EXCEPTION
      'FALHOU T3: tecnico sem quotations.write cancelou orcamento — 0039 foi revertida?';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T3: tecnico sem quotations.write nao cancela orcamento';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T4: REGRESSAO 0039 — tecnico (sem work_orders.manage) NAO cancela OS
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  UPDATE quotations SET status = 'approved' WHERE id = v_quotation2_id;

  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_ALPHA')::text, true);
  SELECT convert_approved_quotation_to_work_order(v_quotation2_id) INTO v_wo;
  v_wo_id := (v_wo->>'id')::uuid;

  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_TECH')::text, true);

  BEGIN
    PERFORM cancel_work_order(v_wo_id, 'Tecnico tentando cancelar OS.');
    RAISE EXCEPTION
      'FALHOU T4: tecnico sem work_orders.manage cancelou OS — 0039 foi revertida?';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T4: tecnico sem work_orders.manage nao cancela OS';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T5: isolamento — beta nao ve historico de status do alpha
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SET LOCAL role = authenticated;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', :'USER_BETA')::text, true);

  SELECT COUNT(*) INTO v_count
  FROM quotation_status_history
  WHERE quotation_id = v_quotation_id;
  IF v_count > 0 THEN
    RAISE EXCEPTION 'FALHOU T5: beta_owner viu historico de status do tenant alpha';
  END IF;
  RAISE NOTICE 'PASSOU T5: beta_owner nao ve quotation_status_history do alpha';

  -- ─────────────────────────────────────────────────────────────────────────
  -- T6: isolamento — beta nao cancela orcamento do alpha
  -- ─────────────────────────────────────────────────────────────────────────
  BEGIN
    PERFORM cancel_quotation(v_quotation2_id, 'Invasor cross tenant.');
    RAISE EXCEPTION 'FALHOU T6: beta_owner cancelou orcamento do tenant alpha';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'PASSOU T6: beta_owner nao cancela orcamento do tenant alpha';
  END;

  -- ─────────────────────────────────────────────────────────────────────────
  -- T7: auditoria — cancelamentos geraram audit_log (adicionado em 0039)
  -- ─────────────────────────────────────────────────────────────────────────
  RESET role;
  SELECT COUNT(*) INTO v_count
  FROM audit_logs
  WHERE action = 'quotation.cancelled' AND tenant_id = :'TENANT_ALPHA';

  IF v_count < 1 THEN
    RAISE EXCEPTION
      'FALHOU T7: cancelamento nao gerou audit_log — 0039 foi revertida? (count=%)', v_count;
  END IF;
  RAISE NOTICE 'PASSOU T7: % evento(s) de auditoria de cancelamento', v_count;

  RAISE NOTICE '=== Testes F2 (cancelamentos) concluidos ===';
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

-- =============================================================================
-- Migration: 0057_work_order_state_machine
-- Descricao: Maquina de estados da OS, guarda de cobranca e permissoes do
--            usuario corrente — correcoes P0 do critique da tela de OS
-- Depende de: 0001_foundation, 0008_work_orders, 0013_financials_minimum
-- Rollback: supabase/rollbacks/0057_work_order_state_machine_rollback.sql
--
-- ORIGEM (tres defeitos independentes, mesma tela):
--
-- 1. `transition_work_order` validava apenas se o status era um nome conhecido
--    e se o atual nao era terminal. Qualquer status -> qualquer status passava,
--    inclusive `opened` -> `done`: OS fechada sem uma hora lancada, sem
--    material, sem evidencia e sem aceite. E, uma vez `done`, nada mais muda.
--
-- 2. `create_receivable_from_work_order` nao olhava o status. A unica guarda
--    era `total_cents <= 0`. Uma OS recem-criada a partir de orcamento
--    aprovado ja nasce com valor, entao um toque gerava cobranca de servico
--    que nunca foi prestado.
--
-- 3. A interface nao tinha como saber o que o usuario pode fazer: nao existia
--    forma de ler as permissoes do papel. O resultado era oferecer botao que o
--    banco ia recusar — o tecnico via "Gerar cobranca" habilitado sem ter
--    `financials.write`.
--
-- DECISAO: a maquina de estados mora no banco, que e a fronteira de confianca.
-- O app espelha as mesmas regras (WorkOrderStatus.allowedNext) para nao
-- oferecer o que sera recusado, mas quem decide e aqui.
-- =============================================================================

-- ── Transicoes permitidas ───────────────────────────────────────────────────
-- Uma OS so vira `done` a partir de execucao (`in_progress`) ou de espera pelo
-- cliente (`awaiting_customer`). Nao existe atalho de `opened` para concluida.
-- `draft` e `scheduled` entram aqui porque a tabela os aceita desde a 0008,
-- ainda que a RPC antiga os ignorasse.
CREATE OR REPLACE FUNCTION _sf_work_order_can_transition(
  p_from text,
  p_to text
) RETURNS boolean LANGUAGE sql IMMUTABLE
SET search_path = public
AS $$
  SELECT p_to = ANY (
    CASE p_from
      WHEN 'draft'             THEN ARRAY['opened','cancelled']
      WHEN 'opened'            THEN ARRAY['scheduled','in_progress','cancelled']
      WHEN 'scheduled'         THEN ARRAY['opened','in_progress','cancelled']
      WHEN 'in_progress'       THEN ARRAY['paused','awaiting_customer','done','cancelled']
      WHEN 'awaiting_customer' THEN ARRAY['in_progress','done','cancelled']
      WHEN 'paused'            THEN ARRAY['in_progress','awaiting_customer','cancelled']
      ELSE ARRAY[]::text[]  -- done e cancelled sao terminais
    END
  );
$$;

CREATE OR REPLACE FUNCTION transition_work_order(
  p_work_order_id uuid,
  p_to_status text,
  p_notes text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_current work_orders;
  v_event text;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL OR NOT (has_permission('work_orders.execute') OR has_permission('work_orders.manage')) THEN
    RAISE EXCEPTION 'Permissao insuficiente para executar OS.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_current
  FROM work_orders
  WHERE id = p_work_order_id AND tenant_id = v_tenant_id;

  IF v_current.id IS NULL THEN
    RAISE EXCEPTION 'OS nao encontrada.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_to_status NOT IN ('draft','opened','scheduled','in_progress','awaiting_customer','paused','done','cancelled') THEN
    RAISE EXCEPTION 'Status de OS invalido.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_current.status IN ('done','cancelled') THEN
    RAISE EXCEPTION 'OS finalizada nao pode mudar de status.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- Repetir o status atual nao e erro: dois toques na rede instavel do campo
  -- nao devem virar mensagem de falha. Sai sem gravar evento duplicado.
  IF v_current.status = p_to_status THEN
    RETURN _work_order_json(p_work_order_id);
  END IF;

  IF NOT _sf_work_order_can_transition(v_current.status, p_to_status) THEN
    RAISE EXCEPTION 'OS % nao pode passar para %.',
      v_current.status, p_to_status
      USING ERRCODE = 'check_violation';
  END IF;

  UPDATE work_orders
  SET status = p_to_status,
      completed_at = CASE WHEN p_to_status = 'done' THEN now() ELSE completed_at END
  WHERE id = p_work_order_id;

  v_event := CASE p_to_status
    WHEN 'in_progress' THEN 'started'
    WHEN 'paused' THEN 'paused'
    WHEN 'done' THEN 'completed'
    WHEN 'cancelled' THEN 'cancelled'
    ELSE 'note'
  END;

  INSERT INTO work_order_events (
    tenant_id, work_order_id, event_type, notes, created_by
  ) VALUES (
    v_tenant_id, p_work_order_id, v_event, p_notes, auth.uid()
  );

  PERFORM log_audit(
    v_tenant_id,
    'work_order.status_changed',
    'work_orders',
    p_work_order_id::text,
    jsonb_build_object('status', v_current.status),
    jsonb_build_object('status', p_to_status)
  );

  RETURN _work_order_json(p_work_order_id);
END;
$$;

-- ── Cobranca so depois de concluir ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION create_receivable_from_work_order(
  p_work_order_id uuid,
  p_due_date date DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_work_order work_orders;
  v_receivable_id uuid;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL OR NOT has_permission('financials.write') THEN
    RAISE EXCEPTION 'Permissao insuficiente para criar recebivel.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_work_order
  FROM work_orders
  WHERE id = p_work_order_id AND tenant_id = v_tenant_id;

  IF v_work_order.id IS NULL THEN
    RAISE EXCEPTION 'OS nao encontrada.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  -- Cobrar servico nao prestado e o defeito mais caro que esta tela podia ter.
  IF v_work_order.status <> 'done' THEN
    RAISE EXCEPTION 'Só é possível gerar cobrança de OS concluída.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_work_order.total_cents <= 0 THEN
    RAISE EXCEPTION 'OS sem valor financeiro.'
      USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO receivables (
    tenant_id, work_order_id, customer_id, description, due_date,
    amount_cents, balance_cents, status
  ) VALUES (
    v_tenant_id,
    v_work_order.id,
    v_work_order.customer_id,
    'OS #' || lpad(v_work_order.number::text, 5, '0') || ' - ' || v_work_order.title,
    COALESCE(p_due_date, CURRENT_DATE),
    v_work_order.total_cents,
    v_work_order.total_cents,
    'open'
  )
  ON CONFLICT (tenant_id, work_order_id) WHERE work_order_id IS NOT NULL
  DO UPDATE SET updated_at = now()
  RETURNING id INTO v_receivable_id;

  PERFORM log_audit(
    v_tenant_id,
    'financial.receivable.created_from_work_order',
    'receivables',
    v_receivable_id::text,
    NULL,
    jsonb_build_object('work_order_id', p_work_order_id)
  );

  RETURN (
    SELECT to_jsonb(r) FROM receivables r WHERE r.id = v_receivable_id
  );
END;
$$;

-- ── Permissoes do usuario corrente ──────────────────────────────────────────
-- A interface precisa saber o que pode oferecer. Sem isto, a alternativa era
-- duplicar a matriz de permissoes no Dart, que sairia do ar assim que alguem
-- mexesse em `role_permissions`. Aqui a fonte da verdade continua uma so.
CREATE OR REPLACE FUNCTION my_permissions()
RETURNS text[] LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(array_agg(DISTINCT p.key), ARRAY[]::text[])
  FROM   tenant_memberships tm
  JOIN   role_permissions   rp ON rp.role_id = tm.role_id
  JOIN   permissions        p  ON p.id       = rp.permission_id
  WHERE  tm.user_id = auth.uid()
    AND  tm.status  = 'active';
$$;

GRANT EXECUTE ON FUNCTION my_permissions() TO authenticated;

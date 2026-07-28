-- Rollback: 0057_work_order_state_machine
--
-- Sem perda de dados: nenhuma tabela muda. O que volta é o comportamento
-- permissivo anterior — qualquer status → qualquer status na OS, e cobrança
-- gerável a partir de OS em qualquer estado.
--
-- ATENÇÃO: restaura as versões 0008 e 0013 das duas funções, com o corpo
-- completo. Rodar 0008/0013 de novo NÃO é alternativa — elas recriam tabelas.
--
-- `my_permissions()` é removida: a interface volta a não saber o que o usuário
-- pode fazer e a oferecer ações que o banco recusa.

DROP FUNCTION IF EXISTS my_permissions();

-- ── transition_work_order: versão 0008 (sem máquina de estados) ─────────────
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

  IF p_to_status NOT IN ('opened','scheduled','in_progress','awaiting_customer','paused','done','cancelled') THEN
    RAISE EXCEPTION 'Status de OS invalido.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_current.status IN ('done','cancelled') THEN
    RAISE EXCEPTION 'OS finalizada nao pode mudar de status.'
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

DROP FUNCTION IF EXISTS _sf_work_order_can_transition(text, text);

-- ── create_receivable_from_work_order: versão 0013 (sem guarda de status) ───
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

  RETURN to_jsonb(r)
  FROM receivables r
  WHERE r.id = v_receivable_id;
END;
$$;

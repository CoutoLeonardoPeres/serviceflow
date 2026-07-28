-- =============================================================================
-- Migration: 0056_auto_work_order_on_approval
-- Descricao: Orcamento aprovado gera a OS sozinho — F6-P1
-- Depende de: 0008_work_orders, 0006_quotation_public_flow, 0055_internal_quotation_decision
-- Rollback: supabase/rollbacks/0056_auto_work_order_on_approval_rollback.sql
--
-- ORIGEM: a OS so nascia se alguem clicasse "Gerar OS" no orcamento aprovado.
-- Quando o cliente aprovava pelo link publico ninguem clicava — o orcamento
-- ficava 'approved' e a execucao nunca comecava. E o caminho manual nem
-- estava disponivel para o cliente: `convert_approved_quotation_to_work_order`
-- exige `current_tenant_id()` e `has_permission('work_orders.write')`, que
-- `anon` nao tem.
--
-- DECISAO (escolha do usuario: automatico, por trigger): a criacao da OS sai
-- da RPC e vira `_sf_work_order_from_quotation`, sem checagem de permissao,
-- chamada por um trigger em `quotations`. Quem decide se PODE aprovar continua
-- sendo a funcao de decisao (`decide_quotation` exige quotations.write,
-- `decide_public_quotation` exige token valido). Uma vez aprovado, a OS e
-- consequencia, nao uma segunda autorizacao.
--
-- A RPC antiga continua existindo e agora delega para a mesma funcao, entao
-- existe um unico caminho de criacao — o botao manual vira so um atalho
-- idempotente para orcamentos aprovados antes desta migration.
-- =============================================================================

-- ── Criacao da OS: caminho unico, sem checagem de permissao ─────────────────
-- Idempotente por `work_orders.quotation_id`: chamada duas vezes devolve a
-- mesma OS em vez de duplicar a execucao.
CREATE OR REPLACE FUNCTION _sf_work_order_from_quotation(
  p_quotation_id uuid,
  p_tenant_id uuid
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_quote quotations;
  v_work_order_id uuid;
  v_item quotation_items;
BEGIN
  SELECT * INTO v_quote
  FROM quotations
  WHERE id = p_quotation_id AND tenant_id = p_tenant_id;

  IF v_quote.id IS NULL THEN
    RAISE EXCEPTION 'Orcamento nao encontrado.'
      USING ERRCODE = 'no_data_found';
  END IF;

  IF v_quote.status <> 'approved' THEN
    RAISE EXCEPTION 'Apenas orcamento aprovado pode virar OS.'
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT id INTO v_work_order_id
  FROM work_orders
  WHERE tenant_id = p_tenant_id AND quotation_id = p_quotation_id;

  IF v_work_order_id IS NOT NULL THEN
    RETURN v_work_order_id;
  END IF;

  INSERT INTO work_orders (
    tenant_id, number, customer_id, request_id, quotation_id,
    status, title, description, total_cents
  ) VALUES (
    p_tenant_id, next_sequence(p_tenant_id, 'work_order'), v_quote.customer_id,
    v_quote.request_id, v_quote.id, 'opened',
    'OS do orçamento #' || lpad(v_quote.number::text, 5, '0'),
    COALESCE(v_quote.notes, 'Execução gerada a partir de orçamento aprovado.'),
    v_quote.total_cents
  )
  RETURNING id INTO v_work_order_id;

  FOR v_item IN
    SELECT *
    FROM quotation_items
    WHERE quotation_id = v_quote.id
      AND version_id = v_quote.current_version_id
    ORDER BY created_at
  LOOP
    INSERT INTO work_order_items (
      tenant_id, work_order_id, quotation_item_id, kind,
      description, quantity, unit_price_cents, total_cents
    ) VALUES (
      p_tenant_id, v_work_order_id, v_item.id, v_item.kind,
      v_item.description, v_item.quantity, v_item.unit_price_cents,
      v_item.total_cents
    );
  END LOOP;

  -- `created_by` fica nulo quando a aprovacao vem do link publico: nao existe
  -- usuario logado. A origem real esta no audit_log logo abaixo.
  INSERT INTO work_order_events (
    tenant_id, work_order_id, event_type, notes, created_by
  ) VALUES (
    p_tenant_id, v_work_order_id, 'converted_from_quotation',
    'OS criada a partir de orçamento aprovado.', auth.uid()
  );

  IF v_quote.request_id IS NOT NULL THEN
    UPDATE service_requests
    SET status = 'converted_to_work_order'
    WHERE id = v_quote.request_id
      AND tenant_id = p_tenant_id
      AND status NOT IN ('cancelled','closed');
  END IF;

  PERFORM log_audit(
    p_tenant_id,
    'work_order.created_from_quotation',
    'work_orders',
    v_work_order_id::text,
    NULL,
    jsonb_build_object(
      'quotation_id', p_quotation_id,
      'origin', CASE WHEN auth.uid() IS NULL THEN 'public_link' ELSE 'internal' END
    )
  );

  RETURN v_work_order_id;
END;
$$;

-- ── RPC manual: mantem a checagem de permissao e delega a criacao ───────────
CREATE OR REPLACE FUNCTION convert_approved_quotation_to_work_order(
  p_quotation_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_work_order_id uuid;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL OR NOT has_permission('work_orders.write') THEN
    RAISE EXCEPTION 'Permissao insuficiente para criar OS.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_work_order_id := _sf_work_order_from_quotation(p_quotation_id, v_tenant_id);
  RETURN _work_order_json(v_work_order_id);
END;
$$;

-- ── Trigger: aprovou, virou OS ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION _sf_quotation_approved_trigger()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  PERFORM _sf_work_order_from_quotation(NEW.id, NEW.tenant_id);
  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_quotation_approved_work_order ON quotations;
CREATE TRIGGER trg_quotation_approved_work_order
  AFTER UPDATE OF status ON quotations
  FOR EACH ROW
  WHEN (NEW.status = 'approved' AND OLD.status IS DISTINCT FROM 'approved')
  EXECUTE FUNCTION _sf_quotation_approved_trigger();

REVOKE ALL ON FUNCTION _sf_work_order_from_quotation(uuid, uuid) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION convert_approved_quotation_to_work_order(uuid)
  TO authenticated;

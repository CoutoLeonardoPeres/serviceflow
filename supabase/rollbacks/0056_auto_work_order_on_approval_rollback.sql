-- Rollback: 0056_auto_work_order_on_approval
--
-- Sem perda de dados: as OS já criadas continuam lá. O que volta é o
-- comportamento antigo — a OS só nasce se alguém clicar "Gerar OS", e a
-- aprovação vinda do link público deixa o orçamento parado em 'approved'.
--
-- ATENÇÃO: restaura a versão 0008 de `convert_approved_quotation_to_work_order`
-- (corpo completo, sem delegar). Rodar 0008 de novo NÃO é alternativa — ele
-- recria tabelas.

DROP TRIGGER IF EXISTS trg_quotation_approved_work_order ON quotations;
DROP FUNCTION IF EXISTS _sf_quotation_approved_trigger();

CREATE OR REPLACE FUNCTION convert_approved_quotation_to_work_order(
  p_quotation_id uuid
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_quote quotations;
  v_work_order_id uuid;
  v_item quotation_items;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL OR NOT has_permission('work_orders.write') THEN
    RAISE EXCEPTION 'Permissao insuficiente para criar OS.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_quote
  FROM quotations
  WHERE id = p_quotation_id AND tenant_id = v_tenant_id;

  IF v_quote.id IS NULL THEN
    RAISE EXCEPTION 'Orcamento nao encontrado.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_quote.status <> 'approved' THEN
    RAISE EXCEPTION 'Apenas orcamento aprovado pode virar OS.'
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT id INTO v_work_order_id
  FROM work_orders
  WHERE tenant_id = v_tenant_id AND quotation_id = p_quotation_id;

  IF v_work_order_id IS NULL THEN
    INSERT INTO work_orders (
      tenant_id, number, customer_id, request_id, quotation_id,
      status, title, description, total_cents
    ) VALUES (
      v_tenant_id, next_sequence(v_tenant_id, 'work_order'), v_quote.customer_id,
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
        v_tenant_id, v_work_order_id, v_item.id, v_item.kind,
        v_item.description, v_item.quantity, v_item.unit_price_cents,
        v_item.total_cents
      );
    END LOOP;

    INSERT INTO work_order_events (
      tenant_id, work_order_id, event_type, notes, created_by
    ) VALUES (
      v_tenant_id, v_work_order_id, 'converted_from_quotation',
      'OS criada a partir de orçamento aprovado.', auth.uid()
    );

    IF v_quote.request_id IS NOT NULL THEN
      UPDATE service_requests
      SET status = 'converted_to_work_order'
      WHERE id = v_quote.request_id
        AND tenant_id = v_tenant_id
        AND status NOT IN ('cancelled','closed');
    END IF;

    PERFORM log_audit(
      v_tenant_id,
      'work_order.created_from_quotation',
      'work_orders',
      v_work_order_id::text,
      NULL,
      jsonb_build_object('quotation_id', p_quotation_id)
    );
  END IF;

  RETURN _work_order_json(v_work_order_id);
END;
$$;

DROP FUNCTION IF EXISTS _sf_work_order_from_quotation(uuid, uuid);

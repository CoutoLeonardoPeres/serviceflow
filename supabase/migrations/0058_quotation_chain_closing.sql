-- =============================================================================
-- Migration: 0058_quotation_chain_closing
-- Descricao: Encerramento em cascata e reabertura em 30 dias — F6-P1 (2a parte)
-- Depende de: 0003_service_requests, 0005_quotations, 0008_work_orders,
--             0036_cancellations, 0056_auto_work_order_on_approval
-- Rollback: supabase/rollbacks/0058_quotation_chain_closing_rollback.sql
--
-- ORIGEM: a 0056 fechou a metade de cima da cadeia (orcamento aprovado gera a
-- OS). A metade de baixo continuava aberta: OS concluida deixava o chamado
-- eternamente em `converted_to_work_order`, e orcamento recusado deixava o
-- chamado em `converted_to_quote`. Ninguem fechava nada — a lista de chamados
-- abertos crescia para sempre com trabalho que ja tinha acabado.
--
-- DECISAO (escolha do usuario: automatico por trigger, orcamento e chamado
-- juntos): o fim do trabalho fecha o chamado, venha pela conclusao da OS ou
-- pela recusa do orcamento. O orcamento nao ganha status novo — `approved`,
-- `rejected` e `expired` ja sao terminais; o que faltava era registro, e ele
-- vai para `quotation_status_history`.
--
-- REABERTURA: o cliente que recusou muda de ideia. `reopen_quotation` devolve
-- orcamento e chamado ao jogo dentro de 30 dias da recusa. Depois disso, o
-- caminho e criar um orcamento novo — reabrir proposta de tres meses atras,
-- com preco de tres meses atras, e prejuizo disfarcado de gentileza.
-- =============================================================================

-- ── OS concluida encerra o chamado ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION _sf_close_chain_on_work_order_done()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.request_id IS NOT NULL THEN
    UPDATE service_requests
    SET status = 'closed'
    WHERE id = NEW.request_id
      AND tenant_id = NEW.tenant_id
      AND status NOT IN ('cancelled','closed');
  END IF;

  -- O orcamento ja esta em `approved`, que e terminal. O que faltava era
  -- deixar registrado que a execucao terminou — sem isso, olhando so o
  -- orcamento nao da para saber se a OS foi feita.
  IF NEW.quotation_id IS NOT NULL THEN
    INSERT INTO quotation_status_history (
      tenant_id, quotation_id, status, notes, changed_by
    )
    SELECT NEW.tenant_id, NEW.quotation_id, q.status,
           'OS #' || lpad(NEW.number::text, 5, '0') || ' concluída.',
           auth.uid()
    FROM quotations q
    WHERE q.id = NEW.quotation_id AND q.tenant_id = NEW.tenant_id;
  END IF;

  PERFORM log_audit(
    NEW.tenant_id,
    'work_order.chain_closed',
    'work_orders',
    NEW.id::text,
    NULL,
    jsonb_build_object(
      'request_id', NEW.request_id,
      'quotation_id', NEW.quotation_id
    )
  );

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_work_order_done_closes_chain ON work_orders;
CREATE TRIGGER trg_work_order_done_closes_chain
  AFTER UPDATE OF status ON work_orders
  FOR EACH ROW
  WHEN (NEW.status = 'done' AND OLD.status IS DISTINCT FROM 'done')
  EXECUTE FUNCTION _sf_close_chain_on_work_order_done();

-- ── Orcamento recusado/expirado encerra o chamado ───────────────────────────
CREATE OR REPLACE FUNCTION _sf_close_chain_on_quotation_refused()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.request_id IS NOT NULL THEN
    UPDATE service_requests
    SET status = 'closed'
    WHERE id = NEW.request_id
      AND tenant_id = NEW.tenant_id
      AND status NOT IN ('cancelled','closed');
  END IF;

  PERFORM log_audit(
    NEW.tenant_id,
    'quotation.chain_closed',
    'quotations',
    NEW.id::text,
    jsonb_build_object('status', OLD.status),
    jsonb_build_object('status', NEW.status, 'request_id', NEW.request_id)
  );

  RETURN NULL;
END;
$$;

DROP TRIGGER IF EXISTS trg_quotation_refused_closes_chain ON quotations;
CREATE TRIGGER trg_quotation_refused_closes_chain
  AFTER UPDATE OF status ON quotations
  FOR EACH ROW
  WHEN (NEW.status IN ('rejected','expired')
        AND OLD.status IS DISTINCT FROM NEW.status)
  EXECUTE FUNCTION _sf_close_chain_on_quotation_refused();

-- ── Reabertura em ate 30 dias ───────────────────────────────────────────────
-- A data de referencia e a do ultimo registro do status atual em
-- `quotation_status_history`; sem registro, cai em `updated_at`. Deixar a
-- janela contando de `created_at` seria errado: um orcamento criado ha 60 dias
-- e recusado ontem ainda merece reabertura.
CREATE OR REPLACE FUNCTION quotation_reopen_deadline(p_quotation_id uuid)
RETURNS timestamptz LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(
           (SELECT MAX(h.changed_at)
              FROM quotation_status_history h
              JOIN quotations q2 ON q2.id = h.quotation_id
             WHERE h.quotation_id = p_quotation_id
               AND h.status = q2.status),
           (SELECT q.updated_at FROM quotations q WHERE q.id = p_quotation_id)
         ) + interval '30 days'
  FROM quotations q3
  WHERE q3.id = p_quotation_id
    AND q3.tenant_id = current_tenant_id();
$$;

CREATE OR REPLACE FUNCTION reopen_quotation(
  p_quotation_id uuid,
  p_reason text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_quote quotations;
  v_deadline timestamptz;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL OR NOT has_permission('quotations.write') THEN
    RAISE EXCEPTION 'Permissao insuficiente para reabrir o orcamento.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_quote
  FROM quotations
  WHERE id = p_quotation_id AND tenant_id = v_tenant_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Orcamento nao encontrado.'
      USING ERRCODE = 'no_data_found';
  END IF;

  -- Aprovado nao reabre: virou OS, e reabrir criaria duas execucoes para o
  -- mesmo trabalho. Cancelado tambem nao — foi decisao deliberada da casa.
  IF v_quote.status NOT IN ('rejected','expired') THEN
    RAISE EXCEPTION 'Só orçamento recusado ou expirado pode ser reaberto.'
      USING ERRCODE = 'check_violation';
  END IF;

  v_deadline := quotation_reopen_deadline(p_quotation_id);
  IF v_deadline IS NULL OR now() > v_deadline THEN
    RAISE EXCEPTION 'Prazo de 30 dias para reabrir este orçamento já passou. Crie um novo.'
      USING ERRCODE = 'check_violation';
  END IF;

  UPDATE quotations
  SET status = 'sent'
  WHERE id = p_quotation_id;

  INSERT INTO quotation_status_history (
    tenant_id, quotation_id, status, notes, changed_by
  ) VALUES (
    v_tenant_id, p_quotation_id, 'sent',
    COALESCE(NULLIF(btrim(p_reason), ''), 'Orçamento reaberto.'),
    auth.uid()
  );

  -- Orcamento e chamado voltam juntos: reabrir a proposta sem reabrir o
  -- chamado deixaria o trabalho invisivel na operacao.
  IF v_quote.request_id IS NOT NULL THEN
    UPDATE service_requests
    SET status = 'converted_to_quote'
    WHERE id = v_quote.request_id
      AND tenant_id = v_tenant_id
      AND status = 'closed';
  END IF;

  PERFORM log_audit(
    v_tenant_id,
    'quotation.reopened',
    'quotations',
    p_quotation_id::text,
    jsonb_build_object('status', v_quote.status),
    jsonb_build_object(
      'status', 'sent',
      'request_id', v_quote.request_id,
      'reason', p_reason
    )
  );

  RETURN (SELECT to_jsonb(q) FROM quotations q WHERE q.id = p_quotation_id);
END;
$$;

GRANT EXECUTE ON FUNCTION reopen_quotation(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION quotation_reopen_deadline(uuid) TO authenticated;

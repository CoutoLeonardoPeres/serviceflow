-- =============================================================================
-- Migration: 0055_internal_quotation_decision
-- Descricao: Aprovar/rejeitar orcamento pelo proprio sistema — F6-P4
-- Depende de: 0005_quotations, 0006_quotation_public_flow
-- Rollback: supabase/rollbacks/0055_internal_quotation_decision_rollback.sql
--
-- ORIGEM: a unica forma de aprovar um orcamento era o cliente clicar no link
-- publico (`decide_public_quotation`). Na pratica o cliente responde por
-- telefone, WhatsApp ou pessoalmente, e o operador precisa registrar a
-- resposta — sem isso o orcamento fica preso em 'sent' e nunca vira OS.
--
-- MODELO: mesma tabela de aprovacoes do fluxo publico (`quotation_approvals`),
-- para o historico ficar num lugar so. O que muda e a origem: aqui exige
-- `quotations.write` e grava quem registrou em `approver_name` mais o
-- `auth.uid()` na auditoria.
-- =============================================================================

CREATE OR REPLACE FUNCTION decide_quotation(
  p_quotation_id uuid,
  p_decision text,
  p_approver_name text,
  p_comments text DEFAULT NULL
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_quote quotations;
  v_next_status text;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL OR NOT has_permission('quotations.write') THEN
    RAISE EXCEPTION 'Permissao insuficiente para decidir o orcamento.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_decision NOT IN ('approved','rejected','change_requested') THEN
    RAISE EXCEPTION 'Decisao invalida.'
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT * INTO v_quote
  FROM quotations
  WHERE id = p_quotation_id AND tenant_id = v_tenant_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Orcamento nao encontrado.'
      USING ERRCODE = 'no_data_found';
  END IF;

  IF v_quote.status IN ('approved','cancelled','expired') THEN
    RAISE EXCEPTION 'Orcamento ja encerrado nao aceita nova decisao.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_quote.current_version_id IS NULL THEN
    RAISE EXCEPTION 'Orcamento sem versao ativa.'
      USING ERRCODE = 'check_violation';
  END IF;

  v_next_status := CASE p_decision
    WHEN 'approved' THEN 'approved'
    WHEN 'rejected' THEN 'rejected'
    ELSE 'change_requested'
  END;

  INSERT INTO quotation_approvals (
    tenant_id, quotation_id, version_id, decision, approver_name, comments
  ) VALUES (
    v_tenant_id,
    p_quotation_id,
    v_quote.current_version_id,
    p_decision,
    COALESCE(NULLIF(btrim(p_approver_name), ''), 'Registrado internamente'),
    p_comments
  );

  UPDATE quotations
  SET status = v_next_status
  WHERE id = p_quotation_id;

  PERFORM log_audit(
    v_tenant_id,
    'quotation.decided',
    'quotations',
    p_quotation_id::text,
    jsonb_build_object('status', v_quote.status),
    jsonb_build_object(
      'status', v_next_status,
      'decision', p_decision,
      'origin', 'internal',
      'approver_name', p_approver_name
    )
  );
END;
$$;

GRANT EXECUTE ON FUNCTION decide_quotation(uuid, text, text, text)
  TO authenticated;

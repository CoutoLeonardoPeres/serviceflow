-- =============================================================================
-- Migration: 0006_quotation_public_flow
-- Descricao: Link publico seguro e decisao publica de orcamento — Entrega 6
-- Depende de: 0005_quotations
-- Rollback: supabase/rollbacks/0006_quotation_public_flow_rollback.sql
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

CREATE OR REPLACE FUNCTION create_quotation_public_link(
  p_quotation_id uuid,
  p_expires_at timestamptz DEFAULT NULL
) RETURNS text LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_version_id uuid;
  v_token text;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL OR NOT has_permission('quotations.send') THEN
    RAISE EXCEPTION 'Permissao insuficiente para gerar link.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT current_version_id INTO v_version_id
  FROM quotations
  WHERE id = p_quotation_id
    AND tenant_id = v_tenant_id;

  IF v_version_id IS NULL THEN
    RAISE EXCEPTION 'Orcamento nao encontrado ou sem versao.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');

  INSERT INTO quotation_public_links (
    tenant_id, quotation_id, version_id, token_hash, expires_at, created_by
  ) VALUES (
    v_tenant_id,
    p_quotation_id,
    v_version_id,
    encode(extensions.digest(v_token, 'sha256'), 'hex'),
    COALESCE(p_expires_at, now() + interval '15 days'),
    auth.uid()
  );

  UPDATE quotations
  SET status = CASE WHEN status = 'draft' THEN 'sent' ELSE status END
  WHERE id = p_quotation_id;

  PERFORM log_audit(
    v_tenant_id,
    'quotation.public_link.created',
    'quotations',
    p_quotation_id::text,
    NULL,
    jsonb_build_object('expires_at', COALESCE(p_expires_at, now() + interval '15 days'))
  );

  RETURN v_token;
END;
$$;

CREATE OR REPLACE FUNCTION get_public_quotation(p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_link quotation_public_links;
  v_quote quotations;
  v_customer_name text;
  v_request_title text;
BEGIN
  SELECT * INTO v_link
  FROM quotation_public_links
  WHERE token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
    AND revoked_at IS NULL
    AND expires_at > now();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Link invalido ou expirado.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  UPDATE quotation_public_links
  SET use_count = use_count + 1,
      last_access_at = now()
  WHERE id = v_link.id;

  UPDATE quotations
  SET status = CASE WHEN status = 'sent' THEN 'viewed' ELSE status END
  WHERE id = v_link.quotation_id
  RETURNING * INTO v_quote;

  SELECT name INTO v_customer_name FROM customers WHERE id = v_quote.customer_id;
  SELECT title INTO v_request_title FROM service_requests WHERE id = v_quote.request_id;

  RETURN to_jsonb(v_quote)
    || jsonb_build_object('customers', jsonb_build_object('name', v_customer_name))
    || jsonb_build_object('service_requests', CASE WHEN v_request_title IS NULL THEN NULL ELSE jsonb_build_object('title', v_request_title) END);
END;
$$;

CREATE OR REPLACE FUNCTION decide_public_quotation(
  p_token text,
  p_decision text,
  p_approver_name text,
  p_comments text DEFAULT NULL
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_link quotation_public_links;
  v_next_status text;
BEGIN
  IF p_decision NOT IN ('approved','rejected','change_requested') THEN
    RAISE EXCEPTION 'Decisao invalida.'
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT * INTO v_link
  FROM quotation_public_links
  WHERE token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
    AND revoked_at IS NULL
    AND expires_at > now();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Link invalido ou expirado.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  v_next_status := CASE p_decision
    WHEN 'approved' THEN 'approved'
    WHEN 'rejected' THEN 'rejected'
    ELSE 'change_requested'
  END;

  INSERT INTO quotation_approvals (
    tenant_id, quotation_id, version_id, decision, approver_name, comments
  ) VALUES (
    v_link.tenant_id,
    v_link.quotation_id,
    v_link.version_id,
    p_decision,
    p_approver_name,
    p_comments
  );

  UPDATE quotations
  SET status = v_next_status
  WHERE id = v_link.quotation_id;

  PERFORM log_audit(
    v_link.tenant_id,
    'quotation.public_decision',
    'quotations',
    v_link.quotation_id::text,
    NULL,
    jsonb_build_object('decision', p_decision)
  );
END;
$$;

-- =============================================================================
-- Migration: 0007_quotation_public_revoke
-- Descricao: Revogacao manual de links publicos de orcamento — Entrega 6
-- Depende de: 0006_quotation_public_flow
-- Rollback: supabase/rollbacks/0007_quotation_public_revoke_rollback.sql
-- =============================================================================

CREATE OR REPLACE FUNCTION revoke_quotation_public_links(
  p_quotation_id uuid
) RETURNS integer LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_revoked_count integer;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL OR NOT has_permission('quotations.send') THEN
    RAISE EXCEPTION 'Permissao insuficiente para revogar link.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF NOT EXISTS (
    SELECT 1
    FROM quotations
    WHERE id = p_quotation_id
      AND tenant_id = v_tenant_id
  ) THEN
    RAISE EXCEPTION 'Orcamento nao encontrado.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  UPDATE quotation_public_links
  SET revoked_at = now()
  WHERE quotation_id = p_quotation_id
    AND tenant_id = v_tenant_id
    AND revoked_at IS NULL;

  GET DIAGNOSTICS v_revoked_count = ROW_COUNT;

  PERFORM log_audit(
    v_tenant_id,
    'quotation.public_link.revoked',
    'quotations',
    p_quotation_id::text,
    NULL,
    jsonb_build_object('revoked_count', v_revoked_count)
  );

  RETURN v_revoked_count;
END;
$$;

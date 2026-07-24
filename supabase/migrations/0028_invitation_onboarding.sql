-- =============================================================================
-- Migration: 0028_invitation_onboarding
-- Descrição: Preview público do convite para onboarding de primeiro acesso
-- Aplicar em: development, staging, production
-- Rollback: supabase/rollbacks/0028_invitation_onboarding_rollback.sql
-- =============================================================================

CREATE OR REPLACE FUNCTION get_invitation_preview(
  p_token text
) RETURNS TABLE (
  email text,
  tenant_name text,
  tenant_slug text,
  role_key text,
  role_name text,
  expires_at timestamptz,
  is_valid boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_hash text;
BEGIN
  IF p_token IS NULL OR btrim(p_token) = '' THEN
    RAISE EXCEPTION 'Convite inválido.'
      USING ERRCODE = '22023';
  END IF;

  v_hash := encode(digest(btrim(p_token), 'sha256'), 'hex');

  RETURN QUERY
  SELECT
    ui.email,
    t.name,
    t.slug,
    r.key,
    r.name,
    ui.expires_at,
    (
      ui.accepted_at IS NULL
      AND ui.revoked_at IS NULL
      AND ui.expires_at >= now()
    ) AS is_valid
  FROM user_invitations ui
  JOIN tenants t ON t.id = ui.tenant_id
  JOIN roles r ON r.id = ui.role_id
  WHERE ui.token_hash = v_hash
  LIMIT 1;
END;
$$;

-- =============================================================================
-- Migration: 0064_platform_admin_tenant_overview
-- Descrição: leitura transversal e segura das empresas para o painel master
-- =============================================================================

CREATE OR REPLACE FUNCTION is_platform_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM platform_admins
    WHERE user_id = auth.uid()
  );
$$;

CREATE OR REPLACE FUNCTION list_platform_tenants()
RETURNS TABLE (
  id uuid,
  name text,
  slug text,
  status text,
  plan_key text,
  billing_status text,
  trial_ends_at timestamptz,
  plan_selected_at timestamptz,
  created_at timestamptz,
  active_users bigint,
  active_units bigint
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT is_platform_admin() THEN
    RAISE EXCEPTION 'Acesso restrito ao administrador da plataforma.'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    t.id,
    t.name,
    t.slug,
    t.status,
    t.plan_key,
    t.billing_status,
    t.trial_ends_at,
    t.plan_selected_at,
    t.created_at,
    COUNT(DISTINCT tm.id) FILTER (WHERE tm.status = 'active'),
    COUNT(DISTINCT tu.id) FILTER (WHERE tu.is_active = true)
  FROM tenants t
  LEFT JOIN tenant_memberships tm ON tm.tenant_id = t.id
  LEFT JOIN tenant_units tu ON tu.tenant_id = t.id
  GROUP BY t.id
  ORDER BY t.created_at DESC;
END;
$$;

REVOKE ALL ON FUNCTION list_platform_tenants() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION list_platform_tenants() TO authenticated;


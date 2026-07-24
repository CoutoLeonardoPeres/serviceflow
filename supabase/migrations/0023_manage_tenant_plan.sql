-- =============================================================================
-- Migration: 0023_manage_tenant_plan
-- Descrição: RPC segura para alterar o plano do tenant atual
-- Aplicar em: development, staging, production
-- Rollback: supabase/rollbacks/0023_manage_tenant_plan_rollback.sql
-- =============================================================================

CREATE OR REPLACE FUNCTION update_current_tenant_plan(
  p_plan_key text
) RETURNS tenants
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_row tenants%ROWTYPE;
BEGIN
  v_tenant_id := current_tenant_id();

  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'Nenhum tenant ativo encontrado.'
      USING ERRCODE = '42501';
  END IF;

  IF NOT (
    has_permission('tenant_settings.update')
    OR is_platform_admin()
  ) THEN
    RAISE EXCEPTION 'Usuário sem permissão para alterar o plano.'
      USING ERRCODE = '42501';
  END IF;

  IF p_plan_key NOT IN ('starter', 'professional', 'business', 'enterprise') THEN
    RAISE EXCEPTION 'Plano inválido: %', p_plan_key
      USING ERRCODE = '22023';
  END IF;

  UPDATE tenants
  SET
    plan_key = p_plan_key,
    billing_status = CASE
      WHEN billing_status IS NULL THEN 'active'
      ELSE billing_status
    END,
    updated_at = now()
  WHERE id = v_tenant_id
  RETURNING * INTO v_row;

  PERFORM log_audit(
    v_tenant_id,
    'tenant.plan.updated',
    'tenants',
    v_tenant_id::text,
    NULL,
    jsonb_build_object('plan_key', p_plan_key)
  );

  RETURN v_row;
END;
$$;

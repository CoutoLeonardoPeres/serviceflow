-- =============================================================================
-- Migration: 0029_plan_selection_onboarding
-- Descrição: Marca a seleção inicial do plano no onboarding comercial
-- Aplicar em: development, staging, production
-- Rollback: supabase/rollbacks/0029_plan_selection_onboarding_rollback.sql
-- =============================================================================

ALTER TABLE tenants
  ADD COLUMN IF NOT EXISTS plan_selected_at timestamptz;

COMMENT ON COLUMN tenants.plan_selected_at IS
  'Data em que o tenant confirmou comercialmente o plano inicial durante o onboarding.';

CREATE OR REPLACE FUNCTION complete_current_tenant_plan_selection(
  p_plan_key text DEFAULT NULL
)
RETURNS tenants
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid := auth_tenant_id();
  v_user_id uuid := auth.uid();
  v_role_key text;
  v_target_plan text;
  v_active_users integer;
  v_active_units integer;
  v_user_limit integer;
  v_unit_limit integer;
  v_updated tenants%ROWTYPE;
BEGIN
  IF v_tenant_id IS NULL OR v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuário sem tenant ativo.'
      USING ERRCODE = '42501';
  END IF;

  SELECT r.key
    INTO v_role_key
  FROM tenant_memberships tm
  JOIN roles r ON r.id = tm.role_id
  WHERE tm.tenant_id = v_tenant_id
    AND tm.user_id = v_user_id
    AND tm.status = 'active'
  LIMIT 1;

  IF v_role_key NOT IN ('tenant_owner', 'tenant_admin', 'platform_admin') THEN
    RAISE EXCEPTION 'Usuário sem permissão para confirmar o plano.'
      USING ERRCODE = '42501';
  END IF;

  SELECT COALESCE(p_plan_key, plan_key)
    INTO v_target_plan
  FROM tenants
  WHERE id = v_tenant_id;

  IF v_target_plan NOT IN ('starter', 'professional', 'business', 'enterprise') THEN
    RAISE EXCEPTION 'Plano inválido: %', v_target_plan
      USING ERRCODE = '22023';
  END IF;

  v_user_limit := plan_user_limit(v_target_plan);
  v_unit_limit := plan_unit_limit(v_target_plan);

  SELECT count(*)
    INTO v_active_users
  FROM tenant_memberships
  WHERE tenant_id = v_tenant_id
    AND status = 'active';

  IF v_active_users > v_user_limit THEN
    RAISE EXCEPTION
      'Não é possível confirmar %: há % usuário(s) ativos e o limite do plano é %.',
      v_target_plan,
      v_active_users,
      v_user_limit
      USING ERRCODE = 'P0001';
  END IF;

  SELECT count(*)
    INTO v_active_units
  FROM tenant_units
  WHERE tenant_id = v_tenant_id
    AND is_active = true;

  IF v_active_units > v_unit_limit THEN
    RAISE EXCEPTION
      'Não é possível confirmar %: há % unidade(s) ativas e o limite do plano é %.',
      v_target_plan,
      v_active_units,
      v_unit_limit
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE tenants
  SET
    plan_key = v_target_plan,
    plan_selected_at = COALESCE(plan_selected_at, now()),
    updated_at = now()
  WHERE id = v_tenant_id
  RETURNING * INTO v_updated;

  INSERT INTO audit_logs (
    tenant_id,
    actor_user_id,
    action,
    entity_table,
    entity_id,
    after_data
  )
  VALUES (
    v_tenant_id,
    v_user_id,
    'tenant.plan.selected',
    'tenants',
    v_tenant_id,
    jsonb_build_object('plan_key', v_target_plan)
  );

  RETURN v_updated;
END;
$$;

GRANT EXECUTE ON FUNCTION complete_current_tenant_plan_selection(text) TO authenticated;

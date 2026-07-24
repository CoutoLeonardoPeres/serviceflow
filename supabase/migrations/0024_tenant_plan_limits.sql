-- =============================================================================
-- Migration: 0024_tenant_plan_limits
-- Descrição: Limites operacionais por plano para usuários ativos
-- Aplicar em: development, staging, production
-- Rollback: supabase/rollbacks/0024_tenant_plan_limits_rollback.sql
-- =============================================================================

CREATE OR REPLACE FUNCTION plan_user_limit(
  p_plan_key text
) RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE p_plan_key
    WHEN 'starter' THEN 3
    WHEN 'professional' THEN 10
    WHEN 'business' THEN 50
    WHEN 'enterprise' THEN 999
    ELSE 999
  END;
$$;

CREATE OR REPLACE FUNCTION enforce_tenant_member_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_plan_key text;
  v_limit integer;
  v_active_count integer;
BEGIN
  IF NEW.status <> 'active' THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE'
     AND OLD.status = 'active'
     AND OLD.tenant_id = NEW.tenant_id
     AND OLD.user_id = NEW.user_id THEN
    RETURN NEW;
  END IF;

  SELECT t.plan_key
    INTO v_plan_key
  FROM tenants t
  WHERE t.id = NEW.tenant_id;

  v_limit := plan_user_limit(v_plan_key);

  SELECT COUNT(*)
    INTO v_active_count
  FROM tenant_memberships tm
  WHERE tm.tenant_id = NEW.tenant_id
    AND tm.status = 'active'
    AND (TG_OP <> 'UPDATE' OR tm.id <> NEW.id);

  IF v_active_count >= v_limit THEN
    RAISE EXCEPTION
      'O plano atual permite até % usuário(s) ativos.',
      v_limit
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_tenant_member_limit ON tenant_memberships;

CREATE TRIGGER trg_enforce_tenant_member_limit
  BEFORE INSERT OR UPDATE ON tenant_memberships
  FOR EACH ROW
  EXECUTE FUNCTION enforce_tenant_member_limit();

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
  v_limit integer;
  v_active_count integer;
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

  v_limit := plan_user_limit(p_plan_key);

  SELECT COUNT(*)
    INTO v_active_count
  FROM tenant_memberships tm
  WHERE tm.tenant_id = v_tenant_id
    AND tm.status = 'active';

  IF v_active_count > v_limit THEN
    RAISE EXCEPTION
      'Não é possível mudar para %: há % usuário(s) ativos e o limite do plano é %.',
      p_plan_key,
      v_active_count,
      v_limit
      USING ERRCODE = 'P0001';
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

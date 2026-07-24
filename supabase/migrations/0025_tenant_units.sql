-- =============================================================================
-- Migration: 0025_tenant_units
-- Descrição: Cadastro de unidades do tenant com limite por plano
-- Aplicar em: development, staging, production
-- Rollback: supabase/rollbacks/0025_tenant_units_rollback.sql
-- =============================================================================

CREATE TABLE tenant_units (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name        text        NOT NULL,
  city        text,
  state       text,
  is_primary  boolean     NOT NULL DEFAULT false,
  is_active   boolean     NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE tenant_units IS
  'Unidades, filiais ou bases operacionais da empresa.';

CREATE INDEX idx_tenant_units_tenant_active
  ON tenant_units (tenant_id, is_active, name);

CREATE UNIQUE INDEX uq_tenant_units_primary
  ON tenant_units (tenant_id)
  WHERE is_primary = true;

CREATE TRIGGER trg_tenant_units_updated_at
  BEFORE UPDATE ON tenant_units
  FOR EACH ROW EXECUTE FUNCTION _sf_update_updated_at();

ALTER TABLE tenant_units ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tenant_units_select" ON tenant_units
  FOR SELECT TO authenticated
  USING (tenant_id = current_tenant_id());

CREATE POLICY "tenant_units_manage" ON tenant_units
  FOR ALL TO authenticated
  USING (
    tenant_id = current_tenant_id()
    AND (
      has_permission('tenant_settings.update')
      OR is_platform_admin()
    )
  )
  WITH CHECK (
    tenant_id = current_tenant_id()
    AND (
      has_permission('tenant_settings.update')
      OR is_platform_admin()
    )
  );

CREATE OR REPLACE FUNCTION plan_unit_limit(
  p_plan_key text
) RETURNS integer
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT CASE p_plan_key
    WHEN 'starter' THEN 1
    WHEN 'professional' THEN 2
    WHEN 'business' THEN 10
    WHEN 'enterprise' THEN 999
    ELSE 999
  END;
$$;

CREATE OR REPLACE FUNCTION enforce_tenant_unit_limit()
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
  IF NEW.is_active = false THEN
    RETURN NEW;
  END IF;

  IF TG_OP = 'UPDATE'
     AND OLD.is_active = true
     AND OLD.tenant_id = NEW.tenant_id THEN
    RETURN NEW;
  END IF;

  SELECT t.plan_key
    INTO v_plan_key
  FROM tenants t
  WHERE t.id = NEW.tenant_id;

  v_limit := plan_unit_limit(v_plan_key);

  SELECT COUNT(*)
    INTO v_active_count
  FROM tenant_units tu
  WHERE tu.tenant_id = NEW.tenant_id
    AND tu.is_active = true
    AND (TG_OP <> 'UPDATE' OR tu.id <> NEW.id);

  IF v_active_count >= v_limit THEN
    RAISE EXCEPTION
      'O plano atual permite até % unidade(s) ativas.',
      v_limit
      USING ERRCODE = 'P0001';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_enforce_tenant_unit_limit ON tenant_units;

CREATE TRIGGER trg_enforce_tenant_unit_limit
  BEFORE INSERT OR UPDATE ON tenant_units
  FOR EACH ROW
  EXECUTE FUNCTION enforce_tenant_unit_limit();

CREATE OR REPLACE FUNCTION ensure_single_primary_unit()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NEW.is_primary THEN
    UPDATE tenant_units
    SET is_primary = false
    WHERE tenant_id = NEW.tenant_id
      AND id <> NEW.id
      AND is_primary = true;
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_ensure_single_primary_unit ON tenant_units;

CREATE TRIGGER trg_ensure_single_primary_unit
  BEFORE INSERT OR UPDATE ON tenant_units
  FOR EACH ROW
  EXECUTE FUNCTION ensure_single_primary_unit();

INSERT INTO tenant_units (tenant_id, name, is_primary, is_active)
SELECT t.id, t.name, true, true
FROM tenants t
WHERE NOT EXISTS (
  SELECT 1
  FROM tenant_units tu
  WHERE tu.tenant_id = t.id
);

CREATE OR REPLACE FUNCTION create_tenant_with_owner(
  p_tenant_name text,
  p_tenant_slug text,
  p_owner_id    uuid
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id  uuid;
  v_owner_role uuid;
BEGIN
  IF p_tenant_slug !~ '^[a-z0-9][a-z0-9\-]{1,62}[a-z0-9]$' THEN
    RAISE EXCEPTION 'Slug inválido: %', p_tenant_slug
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT id INTO v_owner_role FROM roles WHERE key = 'tenant_owner';
  IF v_owner_role IS NULL THEN
    RAISE EXCEPTION 'Role tenant_owner não encontrada. Execute o seed primeiro.'
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  INSERT INTO tenants (name, slug)
  VALUES (p_tenant_name, p_tenant_slug)
  RETURNING id INTO v_tenant_id;

  INSERT INTO tenant_settings (tenant_id)
  VALUES (v_tenant_id);

  INSERT INTO tenant_units (tenant_id, name, is_primary, is_active)
  VALUES (v_tenant_id, p_tenant_name, true, true);

  INSERT INTO tenant_memberships (tenant_id, user_id, role_id, status)
  VALUES (v_tenant_id, p_owner_id, v_owner_role, 'active');

  PERFORM log_audit(
    v_tenant_id, 'tenant.created', 'tenants', v_tenant_id::text,
    NULL, jsonb_build_object('name', p_tenant_name, 'slug', p_tenant_slug)
  );

  RETURN v_tenant_id;
END;
$$;

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
  v_user_limit integer;
  v_unit_limit integer;
  v_active_users integer;
  v_active_units integer;
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

  v_user_limit := plan_user_limit(p_plan_key);
  v_unit_limit := plan_unit_limit(p_plan_key);

  SELECT COUNT(*)
    INTO v_active_users
  FROM tenant_memberships tm
  WHERE tm.tenant_id = v_tenant_id
    AND tm.status = 'active';

  IF v_active_users > v_user_limit THEN
    RAISE EXCEPTION
      'Não é possível mudar para %: há % usuário(s) ativos e o limite do plano é %.',
      p_plan_key,
      v_active_users,
      v_user_limit
      USING ERRCODE = 'P0001';
  END IF;

  SELECT COUNT(*)
    INTO v_active_units
  FROM tenant_units tu
  WHERE tu.tenant_id = v_tenant_id
    AND tu.is_active = true;

  IF v_active_units > v_unit_limit THEN
    RAISE EXCEPTION
      'Não é possível mudar para %: há % unidade(s) ativas e o limite do plano é %.',
      p_plan_key,
      v_active_units,
      v_unit_limit
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

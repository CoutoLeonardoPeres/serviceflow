DROP TRIGGER IF EXISTS trg_ensure_single_primary_unit ON tenant_units;
DROP TRIGGER IF EXISTS trg_enforce_tenant_unit_limit ON tenant_units;

DROP FUNCTION IF EXISTS ensure_single_primary_unit();
DROP FUNCTION IF EXISTS enforce_tenant_unit_limit();
DROP FUNCTION IF EXISTS plan_unit_limit(text);

DROP POLICY IF EXISTS "tenant_units_manage" ON tenant_units;
DROP POLICY IF EXISTS "tenant_units_select" ON tenant_units;

DROP TRIGGER IF EXISTS trg_tenant_units_updated_at ON tenant_units;
DROP TABLE IF EXISTS tenant_units;

DROP FUNCTION IF EXISTS complete_current_tenant_plan_selection(text);

ALTER TABLE tenants
  DROP COLUMN IF EXISTS plan_selected_at;

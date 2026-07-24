DROP POLICY IF EXISTS "tenant_settings_select" ON tenant_settings;
DROP POLICY IF EXISTS "tenant_settings_insert" ON tenant_settings;
DROP POLICY IF EXISTS "tenant_settings_update" ON tenant_settings;

DELETE FROM role_permissions rp
USING roles r
WHERE rp.role_id = r.id
  AND r.key = 'platform_admin';

DROP FUNCTION IF EXISTS is_platform_admin();

CREATE POLICY "tenant_settings_select" ON tenant_settings
  FOR SELECT TO authenticated
  USING (tenant_id = current_tenant_id());

CREATE POLICY "tenant_settings_update" ON tenant_settings
  FOR UPDATE TO authenticated
  USING (tenant_id = current_tenant_id() AND has_permission('tenant_settings.update'))
  WITH CHECK (tenant_id = current_tenant_id());

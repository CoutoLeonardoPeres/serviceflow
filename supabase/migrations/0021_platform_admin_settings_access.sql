-- Permite que administradores master da plataforma também acessem e editem
-- configurações do tenant atual, além de liberar INSERT para o upsert.

CREATE OR REPLACE FUNCTION is_platform_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM platform_admins pa
    WHERE pa.user_id = auth.uid()
  );
$$;

-- Garante que a role operacional "platform_admin" também herde permissões
-- quando usada como membership dentro de um tenant.
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM roles r
CROSS JOIN permissions p
WHERE r.key = 'platform_admin'
  AND NOT EXISTS (
    SELECT 1
    FROM role_permissions rp
    WHERE rp.role_id = r.id
      AND rp.permission_id = p.id
  );

DROP POLICY IF EXISTS "tenant_settings_select" ON tenant_settings;
DROP POLICY IF EXISTS "tenant_settings_insert" ON tenant_settings;
DROP POLICY IF EXISTS "tenant_settings_update" ON tenant_settings;

CREATE POLICY "tenant_settings_select" ON tenant_settings
  FOR SELECT TO authenticated
  USING (
    tenant_id = current_tenant_id()
    OR is_platform_admin()
  );

CREATE POLICY "tenant_settings_insert" ON tenant_settings
  FOR INSERT TO authenticated
  WITH CHECK (
    tenant_id = current_tenant_id()
    AND (
      has_permission('tenant_settings.update')
      OR is_platform_admin()
    )
  );

CREATE POLICY "tenant_settings_update" ON tenant_settings
  FOR UPDATE TO authenticated
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

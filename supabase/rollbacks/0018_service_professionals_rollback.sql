DROP FUNCTION IF EXISTS list_tenant_technician_users();

CREATE OR REPLACE FUNCTION list_tenant_technicians()
RETURNS TABLE(user_id uuid, name text, email text, phone text)
LANGUAGE sql SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    tm.user_id,
    COALESCE(p.full_name, 'Tecnico') AS name,
    NULL::text AS email,
    p.phone
  FROM tenant_memberships tm
  JOIN roles r ON r.id = tm.role_id
  LEFT JOIN profiles p ON p.id = tm.user_id
  WHERE tm.tenant_id = current_tenant_id()
    AND tm.status = 'active'
    AND r.key = 'technician'
    AND has_permission('appointments.read')
  ORDER BY p.full_name NULLS LAST;
$$;

DROP POLICY IF EXISTS "service_professionals_update" ON service_professionals;
DROP POLICY IF EXISTS "service_professionals_insert" ON service_professionals;
DROP POLICY IF EXISTS "service_professionals_select" ON service_professionals;
DROP TRIGGER IF EXISTS trg_service_professionals_updated_at ON service_professionals;
DROP TABLE IF EXISTS service_professionals;

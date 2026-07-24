-- Rollback: 0035_list_all_active_professionals_in_schedule
-- Restaura o comportamento anterior de list_tenant_technicians(), definido em
-- 0018_service_professionals.sql, que exigia vínculo com usuário interno
-- (sp.linked_user_id IS NOT NULL) para listar o profissional na agenda.

CREATE OR REPLACE FUNCTION list_tenant_technicians()
RETURNS TABLE(
  professional_id uuid,
  user_id uuid,
  name text,
  email text,
  phone text,
  category text,
  kind text
)
LANGUAGE sql SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    sp.id AS professional_id,
    sp.linked_user_id AS user_id,
    sp.name,
    sp.email,
    sp.phone,
    sp.category,
    sp.kind
  FROM service_professionals sp
  WHERE sp.tenant_id = current_tenant_id()
    AND sp.is_active = true
    AND sp.linked_user_id IS NOT NULL
    AND has_permission('appointments.read')
  ORDER BY sp.category, sp.name;
$$;

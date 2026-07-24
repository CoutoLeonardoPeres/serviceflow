-- Migration: 0035_list_all_active_professionals_in_schedule
-- Descrição: ajusta a lista da agenda para incluir todos os profissionais ativos,
-- mesmo sem vínculo imediato com usuário interno.
-- Nota: renumerada de 0034 para 0035 em 2026-07-24 para resolver colisão de
-- prefixo com 0034_tenant_billing_webhook_events.sql (higiene técnica F0/T0.2).

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
    AND has_permission('appointments.read')
  ORDER BY sp.category, sp.name;
$$;

-- =============================================================================
-- Migration: 0018_service_professionals
-- Descrição: cadastro formal de profissionais/parceiros e integração com agenda
-- Aplicar em: development, staging, production
-- Rollback: supabase/rollbacks/0018_service_professionals_rollback.sql
-- =============================================================================

CREATE TABLE service_professionals (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  linked_user_id  uuid        REFERENCES profiles(id) ON DELETE SET NULL,
  kind            text        NOT NULL DEFAULT 'partner'
                              CHECK (kind IN ('internal', 'partner')),
  category        text        NOT NULL,
  name            text        NOT NULL,
  email           text,
  phone           text,
  notes           text,
  is_active       boolean     NOT NULL DEFAULT true,
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE service_professionals IS
  'Cadastro operacional de profissionais e parceiros por tenant.';

COMMENT ON COLUMN service_professionals.linked_user_id IS
  'Quando preenchido, o profissional pode receber agenda e execução vinculadas ao usuário interno.';

CREATE UNIQUE INDEX uq_service_professionals_linked_user
  ON service_professionals (tenant_id, linked_user_id)
  WHERE linked_user_id IS NOT NULL;

CREATE INDEX idx_service_professionals_tenant_active
  ON service_professionals (tenant_id, is_active, category, name);

CREATE TRIGGER trg_service_professionals_updated_at
  BEFORE UPDATE ON service_professionals
  FOR EACH ROW EXECUTE FUNCTION _sf_update_updated_at();

ALTER TABLE service_professionals ENABLE ROW LEVEL SECURITY;

CREATE POLICY "service_professionals_select" ON service_professionals
  FOR SELECT TO authenticated
  USING (
    tenant_id = current_tenant_id()
    AND has_permission('appointments.read')
  );

CREATE POLICY "service_professionals_insert" ON service_professionals
  FOR INSERT TO authenticated
  WITH CHECK (
    tenant_id = current_tenant_id()
    AND has_permission('appointments.write')
  );

CREATE POLICY "service_professionals_update" ON service_professionals
  FOR UPDATE TO authenticated
  USING (
    tenant_id = current_tenant_id()
    AND has_permission('appointments.write')
  )
  WITH CHECK (
    tenant_id = current_tenant_id()
    AND has_permission('appointments.write')
  );

CREATE OR REPLACE FUNCTION list_tenant_technician_users()
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

INSERT INTO service_professionals (
  tenant_id,
  linked_user_id,
  kind,
  category,
  name,
  phone,
  is_active
)
SELECT
  tm.tenant_id,
  tm.user_id,
  'internal',
  'Técnico',
  COALESCE(p.full_name, 'Tecnico'),
  p.phone,
  true
FROM tenant_memberships tm
JOIN roles r ON r.id = tm.role_id
LEFT JOIN profiles p ON p.id = tm.user_id
WHERE tm.status = 'active'
  AND r.key = 'technician'
  AND NOT EXISTS (
    SELECT 1
    FROM service_professionals sp
    WHERE sp.tenant_id = tm.tenant_id
      AND sp.linked_user_id = tm.user_id
  );

DROP FUNCTION IF EXISTS list_tenant_technicians();

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

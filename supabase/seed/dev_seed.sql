-- =============================================================================
-- Seed de desenvolvimento — NUNCA aplicar em produção ou staging real
-- Cria dois tenants fictícios e usuários de teste para validar isolamento RLS.
-- =============================================================================

-- ATENÇÃO: Este seed assume que os usuários já existem em auth.users.
-- Crie-os pelo painel Supabase (Auth > Users) antes de rodar este script.
-- Anote os UUIDs e substitua os placeholders abaixo.

-- Placeholder UUIDs (substituir pelos reais criados no painel):
-- user_alpha_owner  = '00000000-0000-0000-0000-000000000001'  (dono da Empresa Alpha)
-- user_alpha_tech   = '00000000-0000-0000-0000-000000000002'  (técnico da Empresa Alpha)
-- user_beta_owner   = '00000000-0000-0000-0000-000000000003'  (dono da Empresa Beta)

DO $$
DECLARE
  v_alpha_id     uuid;
  v_beta_id      uuid;
  v_owner_role   uuid;
  v_tech_role    uuid;

  -- Substitua pelos UUIDs reais dos usuários criados no painel:
  c_alpha_owner  uuid := '00000000-0000-0000-0000-000000000001';
  c_alpha_tech   uuid := '00000000-0000-0000-0000-000000000002';
  c_beta_owner   uuid := '00000000-0000-0000-0000-000000000003';
BEGIN
  -- Pular se já existir (idempotente)
  IF EXISTS (SELECT 1 FROM tenants WHERE slug = 'empresa-alpha') THEN
    RAISE NOTICE 'Seed já aplicado. Pulando.';
    RETURN;
  END IF;

  SELECT id INTO v_owner_role FROM roles WHERE key = 'tenant_owner';
  SELECT id INTO v_tech_role  FROM roles WHERE key = 'technician';

  -- Tenant Alpha
  INSERT INTO tenants (id, name, slug)
  VALUES (gen_random_uuid(), 'Empresa Alpha Elétrica', 'empresa-alpha')
  RETURNING id INTO v_alpha_id;

  INSERT INTO tenant_settings (tenant_id, display_name)
  VALUES (v_alpha_id, 'Alpha Elétrica');

  INSERT INTO tenant_memberships (tenant_id, user_id, role_id, status)
  VALUES
    (v_alpha_id, c_alpha_owner, v_owner_role, 'active'),
    (v_alpha_id, c_alpha_tech,  v_tech_role,  'active');

  -- Tenant Beta (isolado — nunca deve cruzar com Alpha)
  INSERT INTO tenants (id, name, slug)
  VALUES (gen_random_uuid(), 'Beta Refrigeração', 'beta-refrigeracao')
  RETURNING id INTO v_beta_id;

  INSERT INTO tenant_settings (tenant_id, display_name)
  VALUES (v_beta_id, 'Beta Refrigeração');

  INSERT INTO tenant_memberships (tenant_id, user_id, role_id, status)
  VALUES (v_beta_id, c_beta_owner, v_owner_role, 'active');

  RAISE NOTICE 'Seed aplicado: Alpha tenant_id=%, Beta tenant_id=%', v_alpha_id, v_beta_id;
END;
$$;

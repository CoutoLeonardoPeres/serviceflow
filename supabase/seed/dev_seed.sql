-- =============================================================================
-- Seed de desenvolvimento — NUNCA aplicar em produção ou staging real
-- Cria dois tenants fictícios e usuários de teste para validar isolamento RLS.
--
-- Atualizado em 2026-07-24: placeholders alinhados com os tokens literais
-- usados em TODOS os arquivos de test/isolation/*.sql (0002 a 0013), para
-- permitir uma única substituição em lote (sed) em vez de editar cada
-- arquivo separadamente. Ver comando pronto em docs/PROJECT_STATE.md /
-- runbook da Fase 1.
-- =============================================================================

-- ATENÇÃO: Este seed assume que os usuários já existem em auth.users.
-- Crie-os via Supabase Auth Admin API ou painel (Auth > Users) antes de
-- rodar este script. Anote os UUIDs retornados e substitua os 5 placeholders
-- de usuário abaixo — e os MESMOS 5 valores em todos os test/isolation/*.sql
-- (mais TENANT_ALPHA/TENANT_BETA, que só existem nos arquivos de teste).
--
-- Placeholders de usuário (usar o MESMO valor em todos os arquivos):
--   a1000000-0000-4000-8000-000000000001  -> USER_ALPHA   (owner da Alpha)
--   a1000000-0000-4000-8000-000000000003  -> USER_TECH    (técnico da Alpha)
--   a1000000-0000-4000-8000-000000000004  -> USER_VIEWER  (viewer da Alpha, só 0002)
--   a1000000-0000-4000-8000-000000000005  -> analista da Alpha (RBAC na Fase 3, sem uso nos testes SQL)
--   b2000000-0000-4000-8000-000000000002  -> USER_BETA    (owner da Beta)
--
-- Os tenant_id reais (TENANT_ALPHA/TENANT_BETA) são gerados automaticamente
-- por este seed via gen_random_uuid() — consulte-os com a query no final
-- deste arquivo e use-os para substituir os placeholders
-- 'a1a1a1a1-a1a1-4a1a-a1a1-a1a1a1a1a1a1' (TENANT_ALPHA) e
-- 'b2b2b2b2-b2b2-4b2b-b2b2-b2b2b2b2b2b2' (TENANT_BETA) em cada arquivo de teste.

DO $$
DECLARE
  v_alpha_id      uuid;
  v_beta_id       uuid;
  v_owner_role    uuid;
  v_tech_role     uuid;
  v_viewer_role   uuid;
  v_analyst_role  uuid;

  -- UUIDs reais dos usuários criados via scripts/create_test_users.sh em 2026-07-26:
  c_alpha_owner   uuid := '86f2f7bb-8894-4434-9f66-6248f76baf29';
  c_alpha_tech    uuid := '52046711-d77a-445d-9138-8b302e84a1ca';
  c_alpha_viewer  uuid := '0d00d588-c4d2-4e79-9a31-ae9aed685e66';
  c_alpha_analyst uuid := 'c05de9c5-48a3-40a9-98b7-0c11ea2bfea4';
  c_beta_owner    uuid := '9797a31d-99bf-4eb7-8d9e-43b3494b7aa7';
BEGIN
  -- Pular se já existir (idempotente)
  IF EXISTS (SELECT 1 FROM tenants WHERE slug = 'empresa-alpha') THEN
    RAISE NOTICE 'Seed já aplicado. Pulando.';
    RETURN;
  END IF;

  SELECT id INTO v_owner_role   FROM roles WHERE key = 'tenant_owner';
  SELECT id INTO v_tech_role    FROM roles WHERE key = 'technician';
  SELECT id INTO v_viewer_role  FROM roles WHERE key = 'viewer';
  SELECT id INTO v_analyst_role FROM roles WHERE key = 'analyst';

  -- Tenant Alpha
  INSERT INTO tenants (id, name, slug)
  VALUES (gen_random_uuid(), 'Empresa Alpha Elétrica', 'empresa-alpha')
  RETURNING id INTO v_alpha_id;

  INSERT INTO tenant_settings (tenant_id, display_name)
  VALUES (v_alpha_id, 'Alpha Elétrica');

  -- O seed precisa de 4 membros ativos na Alpha (owner/tech/viewer/analyst)
  -- para cobrir os testes de isolamento e RBAC. O plano padrão 'starter'
  -- (0022/0024_tenant_plan_limits.sql) permite só 3 ativos — o trigger
  -- enforce_tenant_member_limit() bloquearia o 4º INSERT. Update direto de
  -- plan_key é aceitável aqui por ser seed de dev/teste, não caminho de
  -- produção (que deve usar a RPC update_current_tenant_plan).
  UPDATE tenants SET plan_key = 'professional' WHERE id = v_alpha_id;

  INSERT INTO tenant_memberships (tenant_id, user_id, role_id, status)
  VALUES
    (v_alpha_id, c_alpha_owner,   v_owner_role,   'active'),
    (v_alpha_id, c_alpha_tech,    v_tech_role,    'active'),
    (v_alpha_id, c_alpha_viewer,  v_viewer_role,  'active'),
    (v_alpha_id, c_alpha_analyst, v_analyst_role, 'active');

  -- Tenant Beta (isolado — nunca deve cruzar com Alpha)
  INSERT INTO tenants (id, name, slug)
  VALUES (gen_random_uuid(), 'Beta Refrigeração', 'beta-refrigeracao')
  RETURNING id INTO v_beta_id;

  INSERT INTO tenant_settings (tenant_id, display_name)
  VALUES (v_beta_id, 'Beta Refrigeração');

  INSERT INTO tenant_memberships (tenant_id, user_id, role_id, status)
  VALUES (v_beta_id, c_beta_owner, v_owner_role, 'active');

  RAISE NOTICE 'Seed aplicado: Alpha tenant_id=%, Beta tenant_id=%', v_alpha_id, v_beta_id;
  RAISE NOTICE 'Use estes tenant_id reais para substituir TENANT_ALPHA/TENANT_BETA nos testes.';
END;
$$;

-- Após rodar este seed, confirme os tenant_id reais gerados:
-- SELECT slug, id FROM tenants WHERE slug IN ('empresa-alpha', 'beta-refrigeracao');

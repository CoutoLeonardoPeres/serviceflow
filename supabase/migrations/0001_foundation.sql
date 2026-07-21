-- =============================================================================
-- Migration: 0001_foundation
-- Descrição: Identidade, tenancy, RBAC, auditoria — base de toda a plataforma
-- Aplicar em: development, staging, production
-- Rollback: 0001_foundation_rollback.sql
-- =============================================================================

-- ---------------------------------------------------------------------------
-- Extensões
-- ---------------------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ---------------------------------------------------------------------------
-- TENANTS
-- ---------------------------------------------------------------------------
CREATE TABLE tenants (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  name        text        NOT NULL,
  slug        text        NOT NULL,
  status      text        NOT NULL DEFAULT 'active'
                          CHECK (status IN ('active', 'suspended', 'closed')),
  timezone    text        NOT NULL DEFAULT 'America/Sao_Paulo',
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_tenants_slug UNIQUE (slug)
);

COMMENT ON TABLE tenants IS 'Empresas/clientes do SaaS (multitenancy).';
COMMENT ON COLUMN tenants.slug IS 'Identificador URL-safe único. Não pode mudar após criação.';

-- ---------------------------------------------------------------------------
-- TENANT SETTINGS
-- ---------------------------------------------------------------------------
CREATE TABLE tenant_settings (
  id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  display_name        text,
  logo_path           text,
  primary_color       text,
  quote_validity_days smallint    NOT NULL DEFAULT 30 CHECK (quote_validity_days > 0),
  currency            text        NOT NULL DEFAULT 'BRL',
  settings            jsonb       NOT NULL DEFAULT '{}'::jsonb,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_tenant_settings_tenant UNIQUE (tenant_id)
);

-- ---------------------------------------------------------------------------
-- TENANT SEQUENCES (numeração por tenant)
-- ---------------------------------------------------------------------------
CREATE TABLE tenant_sequences (
  id          uuid    PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid    NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  kind        text    NOT NULL,
  next_value  bigint  NOT NULL DEFAULT 1 CHECK (next_value > 0),
  CONSTRAINT uq_tenant_sequences UNIQUE (tenant_id, kind)
);

COMMENT ON TABLE tenant_sequences IS
  'Sequências numéricas por empresa. Nunca faça UPDATE diretamente — use next_sequence().';

-- ---------------------------------------------------------------------------
-- PROFILES (extensão de auth.users)
-- ---------------------------------------------------------------------------
CREATE TABLE profiles (
  id          uuid        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name   text        NOT NULL,
  phone       text,
  avatar_path text,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE profiles IS 'Dados públicos de usuário, complementares ao auth.users.';

-- ---------------------------------------------------------------------------
-- ROLES
-- ---------------------------------------------------------------------------
CREATE TABLE roles (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  key         text        NOT NULL,
  name        text        NOT NULL,
  description text,
  is_system   boolean     NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_roles_key UNIQUE (key)
);

-- ---------------------------------------------------------------------------
-- PERMISSIONS
-- ---------------------------------------------------------------------------
CREATE TABLE permissions (
  id          uuid  PRIMARY KEY DEFAULT gen_random_uuid(),
  key         text  NOT NULL,
  name        text  NOT NULL,
  description text,
  CONSTRAINT uq_permissions_key UNIQUE (key)
);

-- ---------------------------------------------------------------------------
-- ROLE PERMISSIONS
-- ---------------------------------------------------------------------------
CREATE TABLE role_permissions (
  role_id       uuid NOT NULL REFERENCES roles(id) ON DELETE CASCADE,
  permission_id uuid NOT NULL REFERENCES permissions(id) ON DELETE CASCADE,
  PRIMARY KEY (role_id, permission_id)
);

-- ---------------------------------------------------------------------------
-- TENANT MEMBERSHIPS
-- ---------------------------------------------------------------------------
CREATE TABLE tenant_memberships (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  user_id     uuid        NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  role_id     uuid        NOT NULL REFERENCES roles(id),
  status      text        NOT NULL DEFAULT 'active'
                          CHECK (status IN ('invited', 'active', 'suspended', 'removed')),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_tenant_memberships UNIQUE (tenant_id, user_id)
);

COMMENT ON TABLE tenant_memberships IS
  'Vínculo usuário ↔ empresa. Um usuário pode ter memberships em vários tenants.';

-- ---------------------------------------------------------------------------
-- USER INVITATIONS
-- ---------------------------------------------------------------------------
CREATE TABLE user_invitations (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  email       text        NOT NULL,
  role_id     uuid        NOT NULL REFERENCES roles(id),
  token_hash  text        NOT NULL,
  expires_at  timestamptz NOT NULL,
  accepted_at timestamptz,
  revoked_at  timestamptz,
  created_by  uuid        REFERENCES auth.users(id),
  created_at  timestamptz NOT NULL DEFAULT now(),
  CONSTRAINT uq_user_invitations_token UNIQUE (token_hash)
);

COMMENT ON COLUMN user_invitations.token_hash IS
  'SHA-256 do token. O token em si nunca é armazenado.';

-- ---------------------------------------------------------------------------
-- PLATFORM ADMINS (fora da estrutura de memberships)
-- ---------------------------------------------------------------------------
CREATE TABLE platform_admins (
  user_id     uuid        PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  granted_by  uuid        REFERENCES auth.users(id),
  granted_at  timestamptz NOT NULL DEFAULT now(),
  notes       text
);

COMMENT ON TABLE platform_admins IS
  'Administradores da plataforma SaaS. SEM acesso default a dados de tenant.';

-- ---------------------------------------------------------------------------
-- AUDIT LOGS (INSERT-ONLY — policies proibem UPDATE/DELETE)
-- ---------------------------------------------------------------------------
CREATE TABLE audit_logs (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid        REFERENCES tenants(id),
  actor_id     uuid        REFERENCES auth.users(id),
  action       text        NOT NULL,
  entity       text        NOT NULL,
  entity_id    text,
  before_data  jsonb,
  after_data   jsonb,
  origin       text,
  request_id   text,
  ip_address   text,
  user_agent   text,
  metadata     jsonb       NOT NULL DEFAULT '{}'::jsonb,
  created_at   timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE audit_logs IS
  'Trilha de auditoria imutável. Nunca inclua senhas, tokens ou dados de cartão.';

-- ---------------------------------------------------------------------------
-- ÍNDICES
-- ---------------------------------------------------------------------------
CREATE INDEX idx_tenant_memberships_tenant ON tenant_memberships(tenant_id);
CREATE INDEX idx_tenant_memberships_user   ON tenant_memberships(user_id);
CREATE INDEX idx_tenant_memberships_status ON tenant_memberships(status) WHERE status = 'active';

CREATE INDEX idx_user_invitations_token    ON user_invitations(token_hash);
CREATE INDEX idx_user_invitations_email    ON user_invitations(email, tenant_id);
CREATE INDEX idx_user_invitations_expires  ON user_invitations(expires_at) WHERE accepted_at IS NULL AND revoked_at IS NULL;

CREATE INDEX idx_audit_logs_tenant         ON audit_logs(tenant_id, created_at DESC);
CREATE INDEX idx_audit_logs_actor          ON audit_logs(actor_id, created_at DESC);
CREATE INDEX idx_audit_logs_entity         ON audit_logs(entity, entity_id);

-- ---------------------------------------------------------------------------
-- TRIGGER: updated_at automático
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _sf_update_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_tenants_updated_at
  BEFORE UPDATE ON tenants
  FOR EACH ROW EXECUTE FUNCTION _sf_update_updated_at();

CREATE TRIGGER trg_tenant_settings_updated_at
  BEFORE UPDATE ON tenant_settings
  FOR EACH ROW EXECUTE FUNCTION _sf_update_updated_at();

CREATE TRIGGER trg_profiles_updated_at
  BEFORE UPDATE ON profiles
  FOR EACH ROW EXECUTE FUNCTION _sf_update_updated_at();

CREATE TRIGGER trg_tenant_memberships_updated_at
  BEFORE UPDATE ON tenant_memberships
  FOR EACH ROW EXECUTE FUNCTION _sf_update_updated_at();

-- ---------------------------------------------------------------------------
-- TRIGGER: criar perfil automaticamente ao criar usuário
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _sf_handle_new_user()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO profiles (id, full_name)
  VALUES (
    NEW.id,
    COALESCE(
      NEW.raw_user_meta_data->>'full_name',
      SPLIT_PART(NEW.email, '@', 1)
    )
  );
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION _sf_handle_new_user();

-- ---------------------------------------------------------------------------
-- FUNÇÕES HELPER (SECURITY DEFINER com search_path fixo)
-- ---------------------------------------------------------------------------

-- Retorna o tenant_id da membership ativa do usuário corrente.
-- Usado em RLS. Assume 1 tenant ativo por usuário (MVP).
CREATE OR REPLACE FUNCTION current_tenant_id()
RETURNS uuid LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT tenant_id
  FROM   tenant_memberships
  WHERE  user_id = auth.uid()
    AND  status  = 'active'
  LIMIT  1;
$$;

-- Verifica se o usuário corrente tem a permissão em seu tenant ativo.
CREATE OR REPLACE FUNCTION has_permission(perm_key text)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM   tenant_memberships tm
    JOIN   role_permissions   rp ON rp.role_id       = tm.role_id
    JOIN   permissions         p  ON p.id             = rp.permission_id
    WHERE  tm.user_id = auth.uid()
      AND  tm.status  = 'active'
      AND  p.key      = perm_key
  );
$$;

-- Retorna e incrementa atomicamente a próxima sequência por tenant.
-- Thread-safe (ON CONFLICT … DO UPDATE com lock implícito).
CREATE OR REPLACE FUNCTION next_sequence(p_tenant_id uuid, p_kind text)
RETURNS bigint LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_next bigint;
BEGIN
  INSERT INTO tenant_sequences (tenant_id, kind, next_value)
  VALUES (p_tenant_id, p_kind, 2)
  ON CONFLICT (tenant_id, kind) DO UPDATE
    SET next_value = tenant_sequences.next_value + 1
  RETURNING next_value - 1 INTO v_next;

  RETURN v_next;
END;
$$;

-- Insere registro de auditoria (chamado por Edge Functions e código servidor).
-- NUNCA registre: senha, token, chave, número de cartão, CVV.
CREATE OR REPLACE FUNCTION log_audit(
  p_tenant_id   uuid,
  p_action      text,
  p_entity      text,
  p_entity_id   text    DEFAULT NULL,
  p_before_data jsonb   DEFAULT NULL,
  p_after_data  jsonb   DEFAULT NULL,
  p_metadata    jsonb   DEFAULT '{}'::jsonb
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO audit_logs (
    tenant_id, actor_id, action, entity, entity_id,
    before_data, after_data, metadata
  )
  VALUES (
    p_tenant_id, auth.uid(), p_action, p_entity, p_entity_id,
    p_before_data, p_after_data, p_metadata
  );
END;
$$;

-- Cria tenant + settings + membership do owner em uma transação.
-- Chamado pela Edge Function após signup ou diretamente por platform_admin.
CREATE OR REPLACE FUNCTION create_tenant_with_owner(
  p_tenant_name text,
  p_tenant_slug text,
  p_owner_id    uuid
) RETURNS uuid LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id  uuid;
  v_owner_role uuid;
BEGIN
  -- Valida slug
  IF p_tenant_slug !~ '^[a-z0-9][a-z0-9\-]{1,62}[a-z0-9]$' THEN
    RAISE EXCEPTION 'Slug inválido: %', p_tenant_slug
      USING ERRCODE = 'invalid_parameter_value';
  END IF;

  SELECT id INTO v_owner_role FROM roles WHERE key = 'tenant_owner';
  IF v_owner_role IS NULL THEN
    RAISE EXCEPTION 'Role tenant_owner não encontrada. Execute o seed primeiro.'
      USING ERRCODE = 'foreign_key_violation';
  END IF;

  INSERT INTO tenants (name, slug)
  VALUES (p_tenant_name, p_tenant_slug)
  RETURNING id INTO v_tenant_id;

  INSERT INTO tenant_settings (tenant_id)
  VALUES (v_tenant_id);

  INSERT INTO tenant_memberships (tenant_id, user_id, role_id, status)
  VALUES (v_tenant_id, p_owner_id, v_owner_role, 'active');

  PERFORM log_audit(
    v_tenant_id, 'tenant.created', 'tenants', v_tenant_id::text,
    NULL, jsonb_build_object('name', p_tenant_name, 'slug', p_tenant_slug)
  );

  RETURN v_tenant_id;
END;
$$;

-- ---------------------------------------------------------------------------
-- ROW LEVEL SECURITY
-- ---------------------------------------------------------------------------
ALTER TABLE tenants              ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_settings      ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_sequences     ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles             ENABLE ROW LEVEL SECURITY;
ALTER TABLE roles                ENABLE ROW LEVEL SECURITY;
ALTER TABLE permissions          ENABLE ROW LEVEL SECURITY;
ALTER TABLE role_permissions     ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_memberships   ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_invitations     ENABLE ROW LEVEL SECURITY;
ALTER TABLE platform_admins      ENABLE ROW LEVEL SECURITY;
ALTER TABLE audit_logs           ENABLE ROW LEVEL SECURITY;

-- Deny by default: todas as tabelas têm RLS habilitado e nenhuma policy
-- padrão. Apenas as policies abaixo concedem acesso.

-- tenants: membro ativo vê seu próprio tenant
CREATE POLICY "tenant_member_select" ON tenants
  FOR SELECT TO authenticated
  USING (id = current_tenant_id());

-- tenant_settings: membro ativo vê e owner/admin edita
CREATE POLICY "tenant_settings_select" ON tenant_settings
  FOR SELECT TO authenticated
  USING (tenant_id = current_tenant_id());

CREATE POLICY "tenant_settings_update" ON tenant_settings
  FOR UPDATE TO authenticated
  USING (tenant_id = current_tenant_id() AND has_permission('tenant_settings.update'))
  WITH CHECK (tenant_id = current_tenant_id());

-- profiles: usuário vê e edita o próprio perfil
CREATE POLICY "profiles_own_select" ON profiles
  FOR SELECT TO authenticated
  USING (id = auth.uid());

CREATE POLICY "profiles_own_update" ON profiles
  FOR UPDATE TO authenticated
  USING (id = auth.uid())
  WITH CHECK (id = auth.uid());

-- Membros do mesmo tenant podem ver perfis uns dos outros
CREATE POLICY "profiles_tenant_select" ON profiles
  FOR SELECT TO authenticated
  USING (
    id IN (
      SELECT user_id FROM tenant_memberships
      WHERE tenant_id = current_tenant_id() AND status = 'active'
    )
  );

-- roles: leitura pública para autenticados (roles são globais)
CREATE POLICY "roles_select" ON roles
  FOR SELECT TO authenticated
  USING (true);

-- permissions: leitura pública para autenticados
CREATE POLICY "permissions_select" ON permissions
  FOR SELECT TO authenticated
  USING (true);

-- role_permissions: leitura pública para autenticados
CREATE POLICY "role_permissions_select" ON role_permissions
  FOR SELECT TO authenticated
  USING (true);

-- memberships: usuário vê a própria; admins veem todas do tenant
CREATE POLICY "memberships_own_select" ON tenant_memberships
  FOR SELECT TO authenticated
  USING (user_id = auth.uid());

CREATE POLICY "memberships_tenant_select" ON tenant_memberships
  FOR SELECT TO authenticated
  USING (tenant_id = current_tenant_id() AND has_permission('members.read'));

CREATE POLICY "memberships_manage" ON tenant_memberships
  FOR ALL TO authenticated
  USING (
    tenant_id = current_tenant_id()
    AND has_permission('members.manage')
  )
  WITH CHECK (
    tenant_id = current_tenant_id()
    AND has_permission('members.manage')
  );

-- invitations: admins gerenciam
CREATE POLICY "invitations_select" ON user_invitations
  FOR SELECT TO authenticated
  USING (tenant_id = current_tenant_id() AND has_permission('members.manage'));

CREATE POLICY "invitations_manage" ON user_invitations
  FOR ALL TO authenticated
  USING (tenant_id = current_tenant_id() AND has_permission('members.manage'))
  WITH CHECK (tenant_id = current_tenant_id() AND has_permission('members.manage'));

-- audit_logs: admins leem; INSERT-ONLY via função
CREATE POLICY "audit_logs_select" ON audit_logs
  FOR SELECT TO authenticated
  USING (tenant_id = current_tenant_id() AND has_permission('audit.read'));

-- Proibir UPDATE e DELETE no audit_logs para todos (incluindo owner)
CREATE POLICY "audit_logs_no_update" ON audit_logs
  FOR UPDATE TO authenticated
  USING (false);

CREATE POLICY "audit_logs_no_delete" ON audit_logs
  FOR DELETE TO authenticated
  USING (false);

-- platform_admins: apenas platform_admin vê (nenhuma policy normal permite)
-- Acesso via service_role (Edge Functions) apenas

-- tenant_sequences: sem acesso direto (apenas via next_sequence())

-- ---------------------------------------------------------------------------
-- SEED: Roles do sistema
-- ---------------------------------------------------------------------------
INSERT INTO roles (key, name, description) VALUES
  ('platform_admin',       'Administrador da Plataforma', 'Acesso administrativo ao SaaS — sem acesso default a dados de tenant'),
  ('tenant_owner',         'Proprietário',                'Controle total da empresa'),
  ('tenant_admin',         'Administrador',               'Administração da empresa'),
  ('manager',              'Gerente',                     'Gestão operacional e comercial'),
  ('analyst',              'Analista / Atendente',        'Abertura e acompanhamento de chamados'),
  ('dispatcher',           'Despachante / Agendador',     'Agenda e despacho de técnicos'),
  ('technician',           'Técnico de Campo',            'Execução de OS em campo'),
  ('warehouse_operator',   'Operador de Estoque',         'Movimentação de estoque (Fase 3)'),
  ('financial_operator',   'Operador Financeiro',         'Financeiro e recebimentos'),
  ('partner',              'Parceiro Terceirizado',        'OS atribuídas ao parceiro (Fase 5)'),
  ('customer_portal_user', 'Usuário do Portal',           'Acesso ao portal do cliente'),
  ('viewer',               'Visualizador',                'Somente leitura');

-- ---------------------------------------------------------------------------
-- SEED: Permissions (MVP)
-- ---------------------------------------------------------------------------
INSERT INTO permissions (key, name) VALUES
  -- Configurações
  ('tenant_settings.read',       'Ver configurações da empresa'),
  ('tenant_settings.update',     'Editar configurações da empresa'),
  -- Membros
  ('members.read',               'Ver membros e equipes'),
  ('members.manage',             'Convidar e gerenciar membros'),
  -- Auditoria
  ('audit.read',                 'Acessar trilha de auditoria'),
  -- Clientes (Fase 1)
  ('customers.read',             'Ver clientes'),
  ('customers.write',            'Criar e editar clientes'),
  -- Chamados (Fase 1)
  ('service_requests.read',      'Ver chamados'),
  ('service_requests.write',     'Criar e editar chamados'),
  ('service_requests.manage',    'Gerenciar chamados (cancelar, atribuir)'),
  -- Agenda (Fase 1)
  ('appointments.read',          'Ver agenda'),
  ('appointments.write',         'Criar e editar agendamentos'),
  -- Orçamentos (Fase 1)
  ('quotations.read',            'Ver orçamentos'),
  ('quotations.write',           'Criar e editar orçamentos'),
  ('quotations.send',            'Enviar orçamentos ao cliente'),
  ('quotations.approve_internal','Aprovar orçamentos internamente'),
  ('quotations.discount_override','Aplicar desconto acima do limite padrão'),
  -- OS (Fase 1)
  ('work_orders.read',           'Ver ordens de serviço'),
  ('work_orders.write',          'Criar e editar OS'),
  ('work_orders.execute',        'Executar OS (técnico de campo)'),
  ('work_orders.manage',         'Gerenciar OS (cancelar, reatribuir)'),
  -- Financeiro (Fase 1 básico)
  ('financials.read',            'Ver dados financeiros'),
  ('financials.write',           'Lançar e baixar financeiro'),
  ('financials.refund',          'Realizar estorno');

-- ---------------------------------------------------------------------------
-- SEED: Permissões por role (MVP)
-- Critério: menor privilégio. owner herda tudo; demais por escopo.
-- ---------------------------------------------------------------------------

-- tenant_owner: todas as permissões
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM   roles r, permissions p
WHERE  r.key = 'tenant_owner';

-- tenant_admin: todas exceto discount_override (requer owner)
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM   roles r, permissions p
WHERE  r.key = 'tenant_admin'
  AND  p.key != 'quotations.discount_override';

-- manager: sem gerenciamento de membros nem auditoria nem configurações
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM   roles r, permissions p
WHERE  r.key = 'manager'
  AND  p.key IN (
    'tenant_settings.read',
    'members.read',
    'customers.read', 'customers.write',
    'service_requests.read', 'service_requests.write', 'service_requests.manage',
    'appointments.read', 'appointments.write',
    'quotations.read', 'quotations.write', 'quotations.send', 'quotations.approve_internal',
    'work_orders.read', 'work_orders.write', 'work_orders.manage',
    'financials.read'
  );

-- analyst (atendente): chamados, agenda leitura, orçamento até escrita
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM   roles r, permissions p
WHERE  r.key = 'analyst'
  AND  p.key IN (
    'customers.read', 'customers.write',
    'service_requests.read', 'service_requests.write',
    'appointments.read',
    'quotations.read', 'quotations.write',
    'work_orders.read'
  );

-- dispatcher: foco em agenda e despacho
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM   roles r, permissions p
WHERE  r.key = 'dispatcher'
  AND  p.key IN (
    'customers.read',
    'service_requests.read', 'service_requests.write',
    'appointments.read', 'appointments.write',
    'work_orders.read', 'work_orders.write'
  );

-- technician: apenas execução de OS atribuídas
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM   roles r, permissions p
WHERE  r.key = 'technician'
  AND  p.key IN (
    'customers.read',
    'service_requests.read',
    'appointments.read',
    'work_orders.read', 'work_orders.execute'
  );

-- financial_operator: foco financeiro, sem criação de OS/orçamento
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM   roles r, permissions p
WHERE  r.key = 'financial_operator'
  AND  p.key IN (
    'customers.read',
    'service_requests.read',
    'quotations.read',
    'work_orders.read',
    'financials.read', 'financials.write', 'financials.refund'
  );

-- viewer: somente leitura
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM   roles r, permissions p
WHERE  r.key = 'viewer'
  AND  p.key IN (
    'customers.read',
    'service_requests.read',
    'appointments.read',
    'quotations.read',
    'work_orders.read'
  );

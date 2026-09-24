-- =============================================================================
-- Migration: 0063_master_owner_account
-- Descricao: Owner master permanente da plataforma ServiceFlow
--
-- O usuario abaixo e o proprietario operacional da instalacao. A conta recebe:
--   * tenant_owner em todas as empresas existentes;
--   * platform_admin para administracao transversal;
--   * acesso RLS global nas tabelas tenant-scoped;
--   * protecao contra remocao, suspensao ou downgrade.
--
-- A senha nunca e armazenada nesta migration. A autenticacao continua sendo
-- responsabilidade exclusiva do Supabase Auth.
-- =============================================================================

CREATE OR REPLACE FUNCTION master_owner_user_id()
RETURNS uuid
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT id
  FROM auth.users
  WHERE lower(email) = 'leonardopcouto@gmail.com'
  LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION is_master_owner()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT auth.uid() IS NOT NULL
     AND auth.uid() = master_owner_user_id();
$$;

-- O Owner master tambem e um administrador de plataforma.
INSERT INTO platform_admins (user_id, granted_by, notes)
SELECT u.id, NULL, 'Owner master permanente do ServiceFlow'
FROM auth.users u
WHERE lower(u.email) = 'leonardopcouto@gmail.com'
ON CONFLICT (user_id) DO UPDATE
SET notes = EXCLUDED.notes;

-- Garante Owner ativo em todas as empresas existentes.
INSERT INTO tenant_memberships (tenant_id, user_id, role_id, status)
SELECT t.id, u.id, r.id, 'active'
FROM tenants t
CROSS JOIN auth.users u
JOIN roles r ON r.key = 'tenant_owner'
WHERE lower(u.email) = 'leonardopcouto@gmail.com'
ON CONFLICT (tenant_id, user_id) DO UPDATE
SET role_id = EXCLUDED.role_id,
    status = 'active';

-- Todo novo tenant tambem recebe o Owner master automaticamente.
CREATE OR REPLACE FUNCTION _sf_add_master_owner_to_tenant()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  INSERT INTO tenant_memberships (tenant_id, user_id, role_id, status)
  SELECT NEW.id, u.id, r.id, 'active'
  FROM auth.users u
  JOIN roles r ON r.key = 'tenant_owner'
  WHERE lower(u.email) = 'leonardopcouto@gmail.com'
  ON CONFLICT (tenant_id, user_id) DO UPDATE
  SET role_id = EXCLUDED.role_id,
      status = 'active';
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_add_master_owner_to_tenant ON tenants;
CREATE TRIGGER trg_add_master_owner_to_tenant
  AFTER INSERT ON tenants
  FOR EACH ROW EXECUTE FUNCTION _sf_add_master_owner_to_tenant();

-- Nao permite que a conta master seja suspensa, removida ou rebaixada.
CREATE OR REPLACE FUNCTION _sf_protect_master_owner()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF OLD.user_id = master_owner_user_id() THEN
    IF TG_OP = 'DELETE'
       OR NEW.status <> 'active'
       OR NEW.role_id <> (SELECT id FROM roles WHERE key = 'tenant_owner') THEN
      RAISE EXCEPTION 'A conta Owner master nao pode ser removida, suspensa ou rebaixada.'
        USING ERRCODE = '42501';
    END IF;
  END IF;
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_master_owner_membership ON tenant_memberships;
CREATE TRIGGER trg_protect_master_owner_membership
  BEFORE UPDATE OR DELETE ON tenant_memberships
  FOR EACH ROW EXECUTE FUNCTION _sf_protect_master_owner();

CREATE OR REPLACE FUNCTION _sf_protect_master_owner_platform_admin()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF OLD.user_id = master_owner_user_id() THEN
    RAISE EXCEPTION 'O administrador master nao pode ser removido.'
      USING ERRCODE = '42501';
  END IF;
  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_master_owner_platform_admin ON platform_admins;
CREATE TRIGGER trg_protect_master_owner_platform_admin
  BEFORE UPDATE OR DELETE ON platform_admins
  FOR EACH ROW EXECUTE FUNCTION _sf_protect_master_owner_platform_admin();

-- Nem uma exclusao administrativa direta de auth.users remove a conta master.
CREATE OR REPLACE FUNCTION _sf_protect_master_auth_user_delete()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF lower(OLD.email) = 'leonardopcouto@gmail.com' THEN
    RAISE EXCEPTION 'A conta Owner master nao pode ser excluida.'
      USING ERRCODE = '42501';
  END IF;
  RETURN OLD;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_master_auth_user_delete ON auth.users;
CREATE TRIGGER trg_protect_master_auth_user_delete
  BEFORE DELETE ON auth.users
  FOR EACH ROW EXECUTE FUNCTION _sf_protect_master_auth_user_delete();

-- Se a conta for criada depois desta migration, a promocao acontece no signup.
CREATE OR REPLACE FUNCTION _sf_provision_master_auth_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, auth
AS $$
BEGIN
  IF lower(NEW.email) = 'leonardopcouto@gmail.com' THEN
    INSERT INTO platform_admins (user_id, granted_by, notes)
    VALUES (NEW.id, NULL, 'Owner master permanente do ServiceFlow')
    ON CONFLICT (user_id) DO NOTHING;

    INSERT INTO tenant_memberships (tenant_id, user_id, role_id, status)
    SELECT t.id, NEW.id, r.id, 'active'
    FROM tenants t
    JOIN roles r ON r.key = 'tenant_owner'
    ON CONFLICT (tenant_id, user_id) DO UPDATE
    SET role_id = EXCLUDED.role_id,
        status = 'active';
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_provision_master_auth_user ON auth.users;
CREATE TRIGGER trg_provision_master_auth_user
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION _sf_provision_master_auth_user();

-- A policy existente de platform_admins era deliberadamente fechada. O master
-- precisa consultar seu proprio registro para que a aplicacao possa refletir
-- o papel corretamente.
DROP POLICY IF EXISTS master_owner_platform_admin_select ON platform_admins;
CREATE POLICY master_owner_platform_admin_select ON platform_admins
  FOR SELECT TO authenticated
  USING (is_master_owner() AND user_id = auth.uid());

-- Permite ao Owner master operar transversalmente em qualquer tabela que tenha
-- tenant_id. As policies sao permissivas (OR) e nao removem o isolamento dos
-- demais usuarios.
DO $$
DECLARE
  v_table text;
  v_policy text;
BEGIN
  FOR v_table IN
    SELECT DISTINCT c.table_name
    FROM information_schema.columns c
    WHERE c.table_schema = 'public'
      AND c.column_name = 'tenant_id'
      AND c.table_name NOT IN ('audit_logs')
  LOOP
    v_policy := 'master_owner_all_' || left(regexp_replace(v_table, '[^a-zA-Z0-9_]', '_', 'g'), 40);
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.%I', v_policy, v_table);
    EXECUTE format(
      'CREATE POLICY %I ON public.%I FOR ALL TO authenticated USING (is_master_owner()) WITH CHECK (is_master_owner())',
      v_policy, v_table
    );
  END LOOP;
END;
$$;

COMMENT ON FUNCTION is_master_owner() IS
  'Identifica o Owner master permanente do ServiceFlow.';

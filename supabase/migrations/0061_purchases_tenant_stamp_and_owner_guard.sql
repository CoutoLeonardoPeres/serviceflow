-- =============================================================================
-- Migration: 0061_purchases_tenant_stamp_and_owner_guard
-- Descricao: tenant_id automatico nas tabelas de compras + protecao do dono
-- Depende de: 0001_foundation, 0044_suppliers_purchase_orders,
--             0059_material_catalog_suppliers
-- Rollback: supabase/rollbacks/0061_purchases_tenant_stamp_and_owner_guard_rollback.sql
--
-- ── PROBLEMA 1: "Voce nao tem permissao para esta operacao de compras." ──────
--
-- `customers`, `service_requests`, `appointments` e companhia tem um trigger
-- BEFORE INSERT que faz `NEW.tenant_id := current_tenant_id()`. `suppliers`
-- (0044) nunca teve, e as tabelas do catalogo (0059) seguiram o mesmo engano.
--
-- Sem o trigger, o app precisaria mandar o tenant_id — e nenhum repositorio
-- manda, porque em todo o resto do sistema quem carimba e o banco. Resultado:
-- `tenant_id` chega NULL, a policy compara `NULL = current_tenant_id()`, o
-- resultado e NULL (nao TRUE), o Postgres recusa com 42501 e o app traduz
-- como falta de permissao. O dono da empresa, com todas as permissoes, via
-- "voce nao tem permissao" — a mensagem estava certa sobre o codigo do erro e
-- completamente errada sobre a causa.
--
-- Isto quer dizer que criar fornecedor nunca funcionou desde a 0044 (F3-P3).
--
-- ── PROBLEMA 2: o dono podia ser removido ────────────────────────────────────
--
-- Nada impedia UPDATE/DELETE em `tenant_memberships` deixando a empresa sem
-- `tenant_owner` ativo. Uma empresa sem dono nao tem quem gerencie assinatura,
-- membros nem permissoes: fica inoperante e so um administrador da plataforma
-- resolve, direto no banco. Aqui o banco passa a recusar.
-- =============================================================================

-- ── Carimbo de tenant nas tabelas de compras ────────────────────────────────
CREATE OR REPLACE FUNCTION _sf_stamp_tenant()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- COALESCE e nao atribuicao direta: o importador de precos e outros RPCs
    -- SECURITY DEFINER ja informam o tenant explicitamente.
    NEW.tenant_id := COALESCE(NEW.tenant_id, current_tenant_id());
  ELSE
    -- Trocar o tenant de uma linha existente e sempre erro: moveria o dado
    -- para outra empresa.
    NEW.tenant_id := OLD.tenant_id;
  END IF;

  IF NEW.tenant_id IS NULL THEN
    RAISE EXCEPTION 'Sem empresa ativa na sessao. Faca login novamente.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_suppliers_tenant ON suppliers;
CREATE TRIGGER trg_suppliers_tenant
  BEFORE INSERT OR UPDATE ON suppliers
  FOR EACH ROW EXECUTE FUNCTION _sf_stamp_tenant();

DROP TRIGGER IF EXISTS trg_material_categories_tenant ON material_categories;
CREATE TRIGGER trg_material_categories_tenant
  BEFORE INSERT OR UPDATE ON material_categories
  FOR EACH ROW EXECUTE FUNCTION _sf_stamp_tenant();

DROP TRIGGER IF EXISTS trg_supplier_categories_tenant ON supplier_categories;
CREATE TRIGGER trg_supplier_categories_tenant
  BEFORE INSERT OR UPDATE ON supplier_categories
  FOR EACH ROW EXECUTE FUNCTION _sf_stamp_tenant();

DROP TRIGGER IF EXISTS trg_supplier_products_tenant ON supplier_products;
CREATE TRIGGER trg_supplier_products_tenant
  BEFORE INSERT OR UPDATE ON supplier_products
  FOR EACH ROW EXECUTE FUNCTION _sf_stamp_tenant();

-- ── Protecao do dono da empresa ─────────────────────────────────────────────
-- A empresa precisa ter, sempre, pelo menos um `tenant_owner` ativo. A regra
-- vale para todo mundo, inclusive para o proprio dono: tirar o proprio acesso
-- por engano e o jeito mais comum de uma empresa ficar orfa.
CREATE OR REPLACE FUNCTION _sf_protect_last_owner()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_owner_role uuid;
  v_row tenant_memberships;
  v_remaining int;
BEGIN
  v_row := CASE TG_OP WHEN 'DELETE' THEN OLD ELSE NEW END;

  SELECT id INTO v_owner_role FROM roles WHERE key = 'tenant_owner';
  IF v_owner_role IS NULL THEN
    RETURN v_row;
  END IF;

  -- Só interessa quando a linha afetada ERA de um dono ativo.
  IF TG_OP = 'UPDATE' THEN
    IF NOT (OLD.role_id = v_owner_role AND OLD.status = 'active') THEN
      RETURN NEW;
    END IF;
    -- Continua dono ativo: nada mudou do ponto de vista desta regra.
    IF NEW.role_id = v_owner_role AND NEW.status = 'active' THEN
      RETURN NEW;
    END IF;
  ELSIF TG_OP = 'DELETE' THEN
    IF NOT (OLD.role_id = v_owner_role AND OLD.status = 'active') THEN
      RETURN OLD;
    END IF;
  END IF;

  SELECT COUNT(*) INTO v_remaining
  FROM tenant_memberships
  WHERE tenant_id = v_row.tenant_id
    AND role_id = v_owner_role
    AND status = 'active'
    AND id <> v_row.id;

  IF v_remaining = 0 THEN
    RAISE EXCEPTION
      'Esta empresa ficaria sem proprietário. Promova outro membro a proprietário antes de remover ou rebaixar este.'
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN CASE TG_OP WHEN 'DELETE' THEN OLD ELSE NEW END;
END;
$$;

DROP TRIGGER IF EXISTS trg_protect_last_owner ON tenant_memberships;
CREATE TRIGGER trg_protect_last_owner
  BEFORE UPDATE OR DELETE ON tenant_memberships
  FOR EACH ROW EXECUTE FUNCTION _sf_protect_last_owner();

-- ── Quem e o dono desta empresa ─────────────────────────────────────────────
-- A interface usa para esconder "remover" e "trocar papel" na linha do dono.
-- A protecao real e o trigger acima; isto so evita oferecer o que sera
-- recusado.
CREATE OR REPLACE FUNCTION is_tenant_owner(p_user_id uuid DEFAULT NULL)
RETURNS boolean LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1
    FROM   tenant_memberships tm
    JOIN   roles r ON r.id = tm.role_id
    WHERE  tm.user_id = COALESCE(p_user_id, auth.uid())
      AND  tm.tenant_id = current_tenant_id()
      AND  tm.status = 'active'
      AND  r.key = 'tenant_owner'
  );
$$;

GRANT EXECUTE ON FUNCTION is_tenant_owner(uuid) TO authenticated;

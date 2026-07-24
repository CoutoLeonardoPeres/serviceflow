-- =============================================================================
-- Migration: 0002_customers
-- Descrição: Clientes, contatos, endereços e ativos (equipamentos) — Entrega 3
-- Depende de: 0001_foundation (roles, permissions, tenants, audit_logs, log_audit)
-- Aplicar em: development, staging, production
-- Rollback: 0002_customers_rollback.sql
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pg_trgm WITH SCHEMA extensions;

-- ---------------------------------------------------------------------------
-- CLIENTES
-- ---------------------------------------------------------------------------
CREATE TABLE customers (
  id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  type                text        NOT NULL
                                  CHECK (type IN ('person','company','condominium','public_entity')),
  name                text        NOT NULL CHECK (char_length(name) BETWEEN 2 AND 200),
  trade_name          text        CHECK (trade_name IS NULL OR char_length(trade_name) BETWEEN 2 AND 200),
  -- CPF (11 dígitos) ou CNPJ (14 dígitos) apenas dígitos — validação completa no app
  document            text        CHECK (document IS NULL OR document ~ '^\d{11}$' OR document ~ '^\d{14}$'),
  email               text        CHECK (email IS NULL OR email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  phone               text        CHECK (phone IS NULL OR phone ~ '^\d{10,11}$'),
  notes               text,
  is_active           boolean     NOT NULL DEFAULT true,
  -- Para cenários solicitante ≠ pagador (ex.: condômino ≠ síndico)
  payer_customer_id   uuid        REFERENCES customers(id),
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  created_by          uuid        REFERENCES auth.users(id),
  updated_by          uuid        REFERENCES auth.users(id)
);

COMMENT ON TABLE customers IS
  'Clientes do tenant: pessoa física, empresa, condomínio ou entidade pública.';
COMMENT ON COLUMN customers.document IS
  'CPF (11 dígitos) ou CNPJ (14 dígitos), somente dígitos. Único por tenant quando não nulo.';
COMMENT ON COLUMN customers.payer_customer_id IS
  'Pagador quando diferente do solicitante. Ex.: condomínio paga por unidade condômino.';

-- document único por tenant quando preenchido
CREATE UNIQUE INDEX uq_customers_document_tenant
  ON customers (tenant_id, document)
  WHERE document IS NOT NULL;

-- índices de busca
CREATE INDEX idx_customers_tenant        ON customers(tenant_id);
CREATE INDEX idx_customers_tenant_active ON customers(tenant_id, is_active);
CREATE INDEX idx_customers_name_trgm     ON customers USING gin(name gin_trgm_ops);
CREATE INDEX idx_customers_tenant_name   ON customers(tenant_id, name text_pattern_ops);

-- ---------------------------------------------------------------------------
-- CONTATOS DO CLIENTE
-- ---------------------------------------------------------------------------
CREATE TABLE customer_contacts (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  customer_id uuid        NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  name        text        NOT NULL CHECK (char_length(name) BETWEEN 2 AND 200),
  role        text        CHECK (role IS NULL OR char_length(role) <= 100),
  phone       text        CHECK (phone IS NULL OR phone ~ '^\d{10,11}$'),
  whatsapp    text        CHECK (whatsapp IS NULL OR whatsapp ~ '^\d{10,11}$'),
  email       text        CHECK (email IS NULL OR email ~* '^[^@\s]+@[^@\s]+\.[^@\s]+$'),
  is_primary  boolean     NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  created_by  uuid        REFERENCES auth.users(id)
);

COMMENT ON TABLE customer_contacts IS
  'Pessoas de contato vinculadas ao cliente.';

-- apenas um contato primário por cliente
CREATE UNIQUE INDEX uq_customer_contacts_primary
  ON customer_contacts (customer_id)
  WHERE is_primary = true;

CREATE INDEX idx_customer_contacts_tenant   ON customer_contacts(tenant_id);
CREATE INDEX idx_customer_contacts_customer ON customer_contacts(customer_id);

-- ---------------------------------------------------------------------------
-- ENDEREÇOS DO CLIENTE
-- ---------------------------------------------------------------------------
CREATE TABLE customer_addresses (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  customer_id uuid        NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  label       text        NOT NULL DEFAULT 'Principal'
                          CHECK (char_length(label) BETWEEN 1 AND 100),
  cep         text        NOT NULL CHECK (cep ~ '^\d{8}$'),
  street      text        NOT NULL CHECK (char_length(street) BETWEEN 2 AND 200),
  number      text        NOT NULL CHECK (char_length(number) BETWEEN 1 AND 20),
  complement  text        CHECK (complement IS NULL OR char_length(complement) <= 100),
  district    text        NOT NULL CHECK (char_length(district) BETWEEN 2 AND 100),
  city        text        NOT NULL CHECK (char_length(city) BETWEEN 2 AND 100),
  state       text        NOT NULL
                          CHECK (state IN (
                            'AC','AL','AP','AM','BA','CE','DF','ES','GO',
                            'MA','MT','MS','MG','PA','PB','PR','PE','PI',
                            'RJ','RN','RS','RO','RR','SC','SP','SE','TO'
                          )),
  reference   text        CHECK (reference IS NULL OR char_length(reference) <= 200),
  latitude    numeric(10,7),
  longitude   numeric(10,7),
  is_default  boolean     NOT NULL DEFAULT false,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  created_by  uuid        REFERENCES auth.users(id)
);

COMMENT ON TABLE customer_addresses IS
  'Endereços de atendimento do cliente. Múltiplos por cliente; apenas um padrão.';

-- apenas um endereço padrão por cliente
CREATE UNIQUE INDEX uq_customer_addresses_default
  ON customer_addresses (customer_id)
  WHERE is_default = true;

CREATE INDEX idx_customer_addresses_tenant   ON customer_addresses(tenant_id);
CREATE INDEX idx_customer_addresses_customer ON customer_addresses(customer_id);

-- ---------------------------------------------------------------------------
-- ATIVOS / EQUIPAMENTOS DO CLIENTE
-- ---------------------------------------------------------------------------
CREATE TABLE customer_assets (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  customer_id   uuid        NOT NULL REFERENCES customers(id) ON DELETE CASCADE,
  address_id    uuid        REFERENCES customer_addresses(id) ON DELETE SET NULL,
  name          text        NOT NULL CHECK (char_length(name) BETWEEN 2 AND 200),
  brand         text        CHECK (brand IS NULL OR char_length(brand) <= 100),
  model         text        CHECK (model IS NULL OR char_length(model) <= 100),
  serial_number text        CHECK (serial_number IS NULL OR char_length(serial_number) <= 100),
  notes         text,
  is_active     boolean     NOT NULL DEFAULT true,
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  created_by    uuid        REFERENCES auth.users(id)
);

COMMENT ON TABLE customer_assets IS
  'Equipamentos/ativos do cliente (para OS de manutenção). MVP simples.';

CREATE INDEX idx_customer_assets_tenant   ON customer_assets(tenant_id);
CREATE INDEX idx_customer_assets_customer ON customer_assets(customer_id);

-- ---------------------------------------------------------------------------
-- TRIGGERS: updated_at
-- ---------------------------------------------------------------------------
CREATE TRIGGER trg_customers_updated_at
  BEFORE UPDATE ON customers
  FOR EACH ROW EXECUTE FUNCTION _sf_update_updated_at();

CREATE TRIGGER trg_customer_contacts_updated_at
  BEFORE UPDATE ON customer_contacts
  FOR EACH ROW EXECUTE FUNCTION _sf_update_updated_at();

CREATE TRIGGER trg_customer_addresses_updated_at
  BEFORE UPDATE ON customer_addresses
  FOR EACH ROW EXECUTE FUNCTION _sf_update_updated_at();

CREATE TRIGGER trg_customer_assets_updated_at
  BEFORE UPDATE ON customer_assets
  FOR EACH ROW EXECUTE FUNCTION _sf_update_updated_at();

-- ---------------------------------------------------------------------------
-- TRIGGER: tenant_id e created_by/updated_by automáticos em customers
-- O cliente NUNCA envia tenant_id — servidor deriva da membership ativa.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _sf_set_customer_meta()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Força tenant_id da membership ativa (ignora qualquer valor enviado pelo cliente)
  NEW.tenant_id := current_tenant_id();
  IF NEW.tenant_id IS NULL THEN
    RAISE EXCEPTION 'Nenhuma membership ativa encontrada para o usuário corrente.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.created_by := auth.uid();
    NEW.updated_by := auth.uid();
  ELSIF TG_OP = 'UPDATE' THEN
    NEW.updated_by := auth.uid();
    -- tenant_id não pode mudar após criação
    NEW.tenant_id  := OLD.tenant_id;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_customers_meta
  BEFORE INSERT OR UPDATE ON customers
  FOR EACH ROW EXECUTE FUNCTION _sf_set_customer_meta();

-- ---------------------------------------------------------------------------
-- TRIGGER: tenant_id derivado do customer pai (child tables)
-- Usa SECURITY INVOKER para que o RLS sobre customers se aplique:
-- se o usuário não vê o customer, não pode inserir contatos/endereços nele.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _sf_set_child_customer_meta()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  SELECT tenant_id INTO NEW.tenant_id
  FROM public.customers
  WHERE id = NEW.customer_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Cliente não encontrado ou sem acesso: %', NEW.customer_id
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.created_by := auth.uid();
  END IF;

  -- tenant_id não muda em UPDATE
  IF TG_OP = 'UPDATE' THEN
    NEW.tenant_id := OLD.tenant_id;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_customer_contacts_meta
  BEFORE INSERT OR UPDATE ON customer_contacts
  FOR EACH ROW EXECUTE FUNCTION _sf_set_child_customer_meta();

CREATE TRIGGER trg_customer_addresses_meta
  BEFORE INSERT OR UPDATE ON customer_addresses
  FOR EACH ROW EXECUTE FUNCTION _sf_set_child_customer_meta();

CREATE TRIGGER trg_customer_assets_meta
  BEFORE INSERT OR UPDATE ON customer_assets
  FOR EACH ROW EXECUTE FUNCTION _sf_set_child_customer_meta();

-- ---------------------------------------------------------------------------
-- TRIGGER: Auditoria de clientes
-- NUNCA registra CPF/CNPJ completo (LGPD — dado pessoal sensível).
-- entity_id é o UUID do cliente; permite rastrear sem expor o documento.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION _sf_audit_customer_change()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    PERFORM log_audit(
      NEW.tenant_id,
      'customer.created',
      'customers',
      NEW.id::text,
      NULL,
      jsonb_build_object(
        'name',      NEW.name,
        'type',      NEW.type,
        'is_active', NEW.is_active
        -- document/email omitidos: dados pessoais (LGPD)
      )
    );
  ELSIF TG_OP = 'UPDATE' THEN
    PERFORM log_audit(
      NEW.tenant_id,
      'customer.updated',
      'customers',
      NEW.id::text,
      jsonb_build_object(
        'name',      OLD.name,
        'type',      OLD.type,
        'is_active', OLD.is_active
      ),
      jsonb_build_object(
        'name',      NEW.name,
        'type',      NEW.type,
        'is_active', NEW.is_active
      )
    );
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_customers_audit
  AFTER INSERT OR UPDATE ON customers
  FOR EACH ROW EXECUTE FUNCTION _sf_audit_customer_change();

-- ---------------------------------------------------------------------------
-- ROW LEVEL SECURITY
-- ---------------------------------------------------------------------------
ALTER TABLE customers         ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_addresses ENABLE ROW LEVEL SECURITY;
ALTER TABLE customer_assets   ENABLE ROW LEVEL SECURITY;

-- ── customers ──────────────────────────────────────────────────────────────

-- Membros com customers.read veem todos os clientes do tenant
CREATE POLICY "customers_select" ON customers
  FOR SELECT TO authenticated
  USING (
    tenant_id = current_tenant_id()
    AND has_permission('customers.read')
  );

-- Membros com customers.write inserem (tenant_id sobrescrito pelo trigger)
CREATE POLICY "customers_insert" ON customers
  FOR INSERT TO authenticated
  WITH CHECK (has_permission('customers.write'));

-- Membros com customers.write atualizam clientes do próprio tenant
CREATE POLICY "customers_update" ON customers
  FOR UPDATE TO authenticated
  USING (
    tenant_id = current_tenant_id()
    AND has_permission('customers.write')
  )
  WITH CHECK (
    tenant_id = current_tenant_id()
    AND has_permission('customers.write')
  );

-- Sem DELETE direto — usar is_active = false (soft delete)
-- (ausência de policy DELETE = deny by default)

-- ── customer_contacts ──────────────────────────────────────────────────────

CREATE POLICY "customer_contacts_select" ON customer_contacts
  FOR SELECT TO authenticated
  USING (
    tenant_id = current_tenant_id()
    AND has_permission('customers.read')
  );

CREATE POLICY "customer_contacts_insert" ON customer_contacts
  FOR INSERT TO authenticated
  WITH CHECK (has_permission('customers.write'));

CREATE POLICY "customer_contacts_update" ON customer_contacts
  FOR UPDATE TO authenticated
  USING (
    tenant_id = current_tenant_id()
    AND has_permission('customers.write')
  )
  WITH CHECK (
    tenant_id = current_tenant_id()
    AND has_permission('customers.write')
  );

CREATE POLICY "customer_contacts_delete" ON customer_contacts
  FOR DELETE TO authenticated
  USING (
    tenant_id = current_tenant_id()
    AND has_permission('customers.write')
  );

-- ── customer_addresses ─────────────────────────────────────────────────────

CREATE POLICY "customer_addresses_select" ON customer_addresses
  FOR SELECT TO authenticated
  USING (
    tenant_id = current_tenant_id()
    AND has_permission('customers.read')
  );

CREATE POLICY "customer_addresses_insert" ON customer_addresses
  FOR INSERT TO authenticated
  WITH CHECK (has_permission('customers.write'));

CREATE POLICY "customer_addresses_update" ON customer_addresses
  FOR UPDATE TO authenticated
  USING (
    tenant_id = current_tenant_id()
    AND has_permission('customers.write')
  )
  WITH CHECK (
    tenant_id = current_tenant_id()
    AND has_permission('customers.write')
  );

CREATE POLICY "customer_addresses_delete" ON customer_addresses
  FOR DELETE TO authenticated
  USING (
    tenant_id = current_tenant_id()
    AND has_permission('customers.write')
  );

-- ── customer_assets ────────────────────────────────────────────────────────

CREATE POLICY "customer_assets_select" ON customer_assets
  FOR SELECT TO authenticated
  USING (
    tenant_id = current_tenant_id()
    AND has_permission('customers.read')
  );

CREATE POLICY "customer_assets_insert" ON customer_assets
  FOR INSERT TO authenticated
  WITH CHECK (has_permission('customers.write'));

CREATE POLICY "customer_assets_update" ON customer_assets
  FOR UPDATE TO authenticated
  USING (
    tenant_id = current_tenant_id()
    AND has_permission('customers.write')
  )
  WITH CHECK (
    tenant_id = current_tenant_id()
    AND has_permission('customers.write')
  );

CREATE POLICY "customer_assets_delete" ON customer_assets
  FOR DELETE TO authenticated
  USING (
    tenant_id = current_tenant_id()
    AND has_permission('customers.write')
  );

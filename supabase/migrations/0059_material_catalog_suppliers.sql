-- =============================================================================
-- Migration: 0059_material_catalog_suppliers
-- Descricao: Catalogo de materiais por categoria, cadastro completo de
--            fornecedor e tabela de precos por fornecedor — F7-P1
-- Depende de: 0001_foundation, 0042_stock_ledger, 0044_suppliers_purchase_orders
-- Rollback: supabase/rollbacks/0059_material_catalog_suppliers_rollback.sql
--
-- ORIGEM: `suppliers` (0044) tinha o minimo para emitir pedido de compra —
-- nome, documento, contato. Nao dava para saber o que o fornecedor vende, por
-- quanto, com que prazo, nem qual pedido minimo ele aceita. E `products` nao
-- tinha categoria, entao "material eletrico" e "equipamento de piscina"
-- moravam na mesma lista sem separacao.
--
-- Consequencia pratica: quem monta um orcamento digitava o preco de cabeca.
-- Nao existia fonte de preco no sistema, e portanto nao existia "melhor
-- preco" — havia so o que a pessoa lembrava.
--
-- MODELO:
--   material_categories — arvore rasa de categorias do setor (eletrica,
--     hidraulica, CFTV, piscina, gesso, vidracaria...), com seed por tenant.
--   products.category_id — a que categoria o material pertence.
--   supplier_categories — o que cada fornecedor atende. E o filtro que faz o
--     cadastro de 40 fornecedores continuar navegavel.
--   supplier_products — o preco daquele fornecedor para aquele produto, com o
--     codigo dele (que e o que vem na planilha) e a validade da tabela.
--
-- REPASSE (escolha do usuario: padrao global + excecoes): o markup vive em
-- tres niveis, do mais especifico para o mais geral — produto, categoria,
-- empresa. Quem cadastra 500 itens nao preenche 500 margens; quem precisa
-- de excecao tem onde por.
-- =============================================================================

-- ── Categorias de material ──────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS material_categories (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name        text        NOT NULL CHECK (char_length(name) BETWEEN 2 AND 80),
  -- Margem da categoria em pontos percentuais (30.00 = 30%). NULL herda a
  -- margem padrao da empresa.
  markup_percent numeric(6,2) CHECK (markup_percent IS NULL OR markup_percent >= 0),
  is_active   boolean     NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  created_by  uuid        REFERENCES auth.users(id),
  CONSTRAINT uq_material_categories_tenant_name UNIQUE (tenant_id, name)
);

CREATE INDEX IF NOT EXISTS idx_material_categories_tenant
  ON material_categories (tenant_id, is_active);

ALTER TABLE material_categories ENABLE ROW LEVEL SECURITY;

CREATE POLICY "material_categories_select" ON material_categories
  FOR SELECT USING (tenant_id = current_tenant_id());
CREATE POLICY "material_categories_write" ON material_categories
  FOR ALL USING (
    tenant_id = current_tenant_id() AND has_permission('stock.write')
  ) WITH CHECK (
    tenant_id = current_tenant_id() AND has_permission('stock.write')
  );

-- ── Produto ganha categoria, codigo de barras e marca ───────────────────────
ALTER TABLE products
  ADD COLUMN IF NOT EXISTS category_id uuid REFERENCES material_categories(id),
  ADD COLUMN IF NOT EXISTS barcode text
    CHECK (barcode IS NULL OR char_length(barcode) BETWEEN 6 AND 20),
  ADD COLUMN IF NOT EXISTS brand text
    CHECK (brand IS NULL OR char_length(brand) <= 80),
  -- Excecao de margem no nivel mais especifico. NULL herda da categoria.
  ADD COLUMN IF NOT EXISTS markup_percent numeric(6,2)
    CHECK (markup_percent IS NULL OR markup_percent >= 0);

CREATE INDEX IF NOT EXISTS idx_products_tenant_category
  ON products (tenant_id, category_id);

-- ── Fornecedor: campos que o mercado usa ────────────────────────────────────
ALTER TABLE suppliers
  ADD COLUMN IF NOT EXISTS state_registration text
    CHECK (state_registration IS NULL OR char_length(state_registration) <= 20),
  ADD COLUMN IF NOT EXISTS contact_name text
    CHECK (contact_name IS NULL OR char_length(contact_name) <= 120),
  ADD COLUMN IF NOT EXISTS whatsapp text
    CHECK (whatsapp IS NULL OR char_length(whatsapp) <= 20),
  ADD COLUMN IF NOT EXISTS website text
    CHECK (website IS NULL OR char_length(website) <= 200),
  ADD COLUMN IF NOT EXISTS zip_code text
    CHECK (zip_code IS NULL OR char_length(zip_code) <= 12),
  ADD COLUMN IF NOT EXISTS street text
    CHECK (street IS NULL OR char_length(street) <= 200),
  ADD COLUMN IF NOT EXISTS number text
    CHECK (number IS NULL OR char_length(number) <= 20),
  ADD COLUMN IF NOT EXISTS complement text
    CHECK (complement IS NULL OR char_length(complement) <= 100),
  ADD COLUMN IF NOT EXISTS district text
    CHECK (district IS NULL OR char_length(district) <= 100),
  ADD COLUMN IF NOT EXISTS city text
    CHECK (city IS NULL OR char_length(city) <= 100),
  ADD COLUMN IF NOT EXISTS state text
    CHECK (state IS NULL OR char_length(state) = 2),
  -- Prazo medio de entrega em dias corridos. Alimenta o aviso de "chega em X
  -- dias" no orcamento, e nao entra no ranking de melhor preco.
  ADD COLUMN IF NOT EXISTS lead_time_days smallint
    CHECK (lead_time_days IS NULL OR lead_time_days BETWEEN 0 AND 365),
  ADD COLUMN IF NOT EXISTS payment_terms text
    CHECK (payment_terms IS NULL OR char_length(payment_terms) <= 200),
  ADD COLUMN IF NOT EXISTS min_order_cents integer NOT NULL DEFAULT 0
    CHECK (min_order_cents >= 0),
  ADD COLUMN IF NOT EXISTS delivers boolean NOT NULL DEFAULT true;

-- ── O que cada fornecedor atende ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS supplier_categories (
  supplier_id uuid NOT NULL REFERENCES suppliers(id) ON DELETE CASCADE,
  category_id uuid NOT NULL REFERENCES material_categories(id) ON DELETE CASCADE,
  tenant_id   uuid NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  PRIMARY KEY (supplier_id, category_id)
);

CREATE INDEX IF NOT EXISTS idx_supplier_categories_category
  ON supplier_categories (tenant_id, category_id);

ALTER TABLE supplier_categories ENABLE ROW LEVEL SECURITY;

CREATE POLICY "supplier_categories_select" ON supplier_categories
  FOR SELECT USING (tenant_id = current_tenant_id());
CREATE POLICY "supplier_categories_write" ON supplier_categories
  FOR ALL USING (
    tenant_id = current_tenant_id() AND has_permission('purchases.write')
  ) WITH CHECK (
    tenant_id = current_tenant_id() AND has_permission('purchases.write')
  );

-- ── Preco do fornecedor para o produto ──────────────────────────────────────
CREATE TABLE IF NOT EXISTS supplier_products (
  id            uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid          NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  supplier_id   uuid          NOT NULL REFERENCES suppliers(id) ON DELETE CASCADE,
  product_id    uuid          NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  -- O codigo que o fornecedor usa. E a chave que casa a planilha dele com o
  -- catalogo daqui — por isso e unico por fornecedor.
  supplier_code text          CHECK (supplier_code IS NULL OR char_length(supplier_code) <= 60),
  price_cents   integer       NOT NULL CHECK (price_cents >= 0),
  -- Embalagem de venda: alguns vendem so a caixa com 100.
  pack_quantity numeric(12,3) NOT NULL DEFAULT 1 CHECK (pack_quantity > 0),
  min_quantity  numeric(12,3) NOT NULL DEFAULT 0 CHECK (min_quantity >= 0),
  -- Validade da tabela. Preco vencido nao entra no ranking de melhor preco,
  -- mas continua visivel: sumir sem avisar seria pior.
  valid_until   date,
  is_active     boolean       NOT NULL DEFAULT true,
  updated_at    timestamptz   NOT NULL DEFAULT now(),
  updated_by    uuid          REFERENCES auth.users(id),
  created_at    timestamptz   NOT NULL DEFAULT now(),
  CONSTRAINT uq_supplier_products UNIQUE (supplier_id, product_id),
  CONSTRAINT uq_supplier_products_code UNIQUE (supplier_id, supplier_code)
);

CREATE INDEX IF NOT EXISTS idx_supplier_products_product
  ON supplier_products (tenant_id, product_id, is_active);

ALTER TABLE supplier_products ENABLE ROW LEVEL SECURITY;

CREATE POLICY "supplier_products_select" ON supplier_products
  FOR SELECT USING (tenant_id = current_tenant_id());
CREATE POLICY "supplier_products_write" ON supplier_products
  FOR ALL USING (
    tenant_id = current_tenant_id() AND has_permission('purchases.write')
  ) WITH CHECK (
    tenant_id = current_tenant_id() AND has_permission('purchases.write')
  );

-- Historico de preco: sem isto nao da para responder "quanto isso custava
-- quando fechei aquele orcamento", que e a primeira pergunta quando a margem
-- sai errada.
CREATE TABLE IF NOT EXISTS supplier_price_history (
  id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  supplier_product_id uuid        NOT NULL REFERENCES supplier_products(id) ON DELETE CASCADE,
  price_cents         integer     NOT NULL CHECK (price_cents >= 0),
  source              text        NOT NULL DEFAULT 'manual'
                                  CHECK (source IN ('manual','spreadsheet','purchase_order')),
  changed_at          timestamptz NOT NULL DEFAULT now(),
  changed_by          uuid        REFERENCES auth.users(id)
);

CREATE INDEX IF NOT EXISTS idx_supplier_price_history_item
  ON supplier_price_history (supplier_product_id, changed_at DESC);

ALTER TABLE supplier_price_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "supplier_price_history_select" ON supplier_price_history
  FOR SELECT USING (tenant_id = current_tenant_id());
CREATE POLICY "supplier_price_history_insert" ON supplier_price_history
  FOR INSERT WITH CHECK (
    tenant_id = current_tenant_id() AND has_permission('purchases.write')
  );

-- Append-only por trigger: o historico se escreve sozinho, senao um caminho
-- de atualizacao esquecido deixa buraco justamente onde se quer auditar.
CREATE OR REPLACE FUNCTION _sf_log_supplier_price()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF TG_OP = 'UPDATE' AND NEW.price_cents IS NOT DISTINCT FROM OLD.price_cents THEN
    RETURN NEW;
  END IF;

  INSERT INTO supplier_price_history (
    tenant_id, supplier_product_id, price_cents, source, changed_by
  ) VALUES (
    NEW.tenant_id, NEW.id, NEW.price_cents,
    COALESCE(current_setting('serviceflow.price_source', true), 'manual'),
    auth.uid()
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_supplier_price_history ON supplier_products;
CREATE TRIGGER trg_supplier_price_history
  AFTER INSERT OR UPDATE OF price_cents ON supplier_products
  FOR EACH ROW EXECUTE FUNCTION _sf_log_supplier_price();

-- ── Margem padrao da empresa ────────────────────────────────────────────────
ALTER TABLE tenant_settings
  ADD COLUMN IF NOT EXISTS default_markup_percent numeric(6,2) NOT NULL DEFAULT 30
    CHECK (default_markup_percent >= 0);

-- ── Melhor preco por produto ────────────────────────────────────────────────
-- Resolve numa consulta so o que a tela precisa: qual fornecedor esta mais
-- barato, quanto sai para o cliente com a margem que vale para aquele produto,
-- e se ja existe saldo proprio (que sai na hora, sem compra).
CREATE OR REPLACE FUNCTION best_price_for_product(p_product_id uuid)
RETURNS TABLE (
  supplier_id       uuid,
  supplier_name     text,
  supplier_code     text,
  price_cents       integer,
  markup_percent    numeric,
  client_price_cents integer,
  lead_time_days    smallint,
  valid_until       date,
  is_stale          boolean,
  stock_quantity    numeric,
  stock_avg_cost_cents integer
) LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public
AS $$
  WITH tenant AS (
    SELECT current_tenant_id() AS id
  ),
  markup AS (
    -- Do mais especifico para o mais geral: produto, categoria, empresa.
    SELECT COALESCE(
             p.markup_percent,
             mc.markup_percent,
             ts.default_markup_percent,
             0
           ) AS percent
    FROM products p
    LEFT JOIN material_categories mc ON mc.id = p.category_id
    LEFT JOIN tenant_settings ts ON ts.tenant_id = p.tenant_id
    WHERE p.id = p_product_id
      AND p.tenant_id = (SELECT id FROM tenant)
  ),
  stock AS (
    SELECT COALESCE(SUM(sb.quantity), 0) AS qty,
           CASE WHEN COALESCE(SUM(sb.quantity), 0) > 0
                THEN (SUM(sb.total_value_cents) / SUM(sb.quantity))::integer
                ELSE 0 END AS avg_cost
    FROM stock_balances sb
    WHERE sb.product_id = p_product_id
      AND sb.tenant_id = (SELECT id FROM tenant)
  )
  SELECT
    s.id,
    s.name,
    sp.supplier_code,
    sp.price_cents,
    m.percent,
    round(sp.price_cents * (1 + m.percent / 100.0))::integer,
    s.lead_time_days,
    sp.valid_until,
    (sp.valid_until IS NOT NULL AND sp.valid_until < CURRENT_DATE),
    st.qty,
    st.avg_cost
  FROM supplier_products sp
  JOIN suppliers s ON s.id = sp.supplier_id
  CROSS JOIN markup m
  CROSS JOIN stock st
  WHERE sp.product_id = p_product_id
    AND sp.tenant_id = (SELECT id FROM tenant)
    AND sp.is_active
    AND s.is_active
  -- Tabela vencida vai para o fim: continua visivel, mas nao ganha do preco
  -- que ainda vale.
  ORDER BY
    (sp.valid_until IS NOT NULL AND sp.valid_until < CURRENT_DATE),
    sp.price_cents;
$$;

GRANT EXECUTE ON FUNCTION best_price_for_product(uuid) TO authenticated;

-- ── Seed de categorias do setor ─────────────────────────────────────────────
-- Chamada no onboarding do tenant. Idempotente: rodar de novo nao duplica nem
-- sobrescreve margem que a empresa ja ajustou.
CREATE OR REPLACE FUNCTION seed_material_categories(p_tenant_id uuid DEFAULT NULL)
RETURNS integer LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_count int;
BEGIN
  v_tenant_id := COALESCE(p_tenant_id, current_tenant_id());
  IF v_tenant_id IS NULL OR NOT has_permission('stock.write') THEN
    RAISE EXCEPTION 'Permissao insuficiente para criar categorias.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  INSERT INTO material_categories (tenant_id, name, created_by)
  SELECT v_tenant_id, name, auth.uid()
  FROM (VALUES
    ('Material elétrico'),
    ('Material hidráulico'),
    ('Material de construção'),
    ('Acabamento e pintura'),
    ('Gesso e drywall'),
    ('Vidraçaria e esquadrias'),
    ('Marcenaria e madeira'),
    ('Serralheria e metalurgia'),
    ('Impermeabilização'),
    ('Climatização e refrigeração'),
    ('Equipamentos de piscina'),
    ('CFTV e segurança eletrônica'),
    ('Redes e cabeamento estruturado'),
    ('Automação predial'),
    ('Iluminação'),
    ('Energia solar'),
    ('Bombas e motores'),
    ('Ferramentas e consumíveis'),
    ('EPI e segurança do trabalho'),
    ('Elevadores e transporte vertical'),
    ('Combate a incêndio'),
    ('Jardinagem e paisagismo'),
    ('Limpeza e conservação'),
    ('Equipamentos industriais')
  ) AS seed(name)
  ON CONFLICT (tenant_id, name) DO NOTHING;

  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

GRANT EXECUTE ON FUNCTION seed_material_categories(uuid) TO authenticated;

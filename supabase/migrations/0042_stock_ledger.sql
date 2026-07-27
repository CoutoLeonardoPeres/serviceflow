-- =============================================================================
-- Migration: 0042_stock_ledger
-- Descricao: Nucleo do razao de estoque — produtos, depositos, movimentos e
--            saldos com custo medio ponderado movel — F3-P1
-- Depende de: 0001_foundation
-- Rollback: supabase/rollbacks/0042_stock_ledger_rollback.sql
--
-- DECISOES QUE GOVERNAM ESTE SCHEMA
--
-- ADR-020 (custo medio ponderado movel):
--   stock_balances NAO guarda custo medio como fonte da verdade. Guarda
--   quantity + total_value_cents, e o custo medio e derivado.
--   Isso e deliberado: guardar o custo medio arredondado e recalcula-lo a cada
--   entrada acumula erro de arredondamento a cada movimento. Guardando o valor
--   total em centavos inteiros, o residuo fica no saldo e nunca some.
--
-- ADR-003 (regra critica no servidor):
--   stock_balances so e mutado pelos RPCs abaixo. Nao ha policy de INSERT,
--   UPDATE ou DELETE para o cliente em nenhuma das duas tabelas de razao.
--
-- INVARIANTES:
--   1. stock_movements e append-only. Erro se corrige com movimento contrario.
--   2. Saldo nunca fica negativo. Saida que estouraria o saldo e rejeitada.
--   3. Todo movimento grava o saldo resultante (quantity_after, value_after),
--      para que a auditoria possa reconstruir a linha do tempo sem recalcular.
--   4. Concorrencia: todo RPC trava a linha de saldo com FOR UPDATE antes de
--      ler. Sem isso, duas saidas simultaneas poderiam passar as duas pela
--      checagem de saldo e deixar o estoque negativo.
-- =============================================================================

-- ── Catalogo de produtos ─────────────────────────────────────────────────────
-- Ate aqui, work_order_materials registrava material por texto livre. O
-- catalogo entra agora; a ligacao com a OS (ADR-016) fica para F3-P2.

CREATE TABLE IF NOT EXISTS products (
  id          uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid          NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  sku         text          CHECK (sku IS NULL OR char_length(sku) BETWEEN 1 AND 60),
  name        text          NOT NULL CHECK (char_length(name) BETWEEN 2 AND 200),
  description text          CHECK (description IS NULL OR char_length(description) <= 1000),
  unit        text          NOT NULL DEFAULT 'un'
                            CHECK (unit IN ('un','m','m2','m3','kg','g','l','ml','cx','pc','h')),
  -- Produto de servico ou consumo direto pode existir no catalogo sem controle
  -- de saldo. Movimento so e aceito quando track_stock = true.
  track_stock boolean       NOT NULL DEFAULT true,
  min_quantity numeric(12,3) NOT NULL DEFAULT 0 CHECK (min_quantity >= 0),
  is_active   boolean       NOT NULL DEFAULT true,
  created_at  timestamptz   NOT NULL DEFAULT now(),
  updated_at  timestamptz   NOT NULL DEFAULT now(),
  created_by  uuid          REFERENCES auth.users(id),
  updated_by  uuid          REFERENCES auth.users(id),
  CONSTRAINT uq_products_tenant_sku UNIQUE (tenant_id, sku)
);

CREATE INDEX IF NOT EXISTS idx_products_tenant_active
  ON products (tenant_id, is_active, name);

DROP TRIGGER IF EXISTS trg_products_updated_at ON products;
CREATE TRIGGER trg_products_updated_at
  BEFORE UPDATE ON products
  FOR EACH ROW EXECUTE FUNCTION _sf_update_updated_at();

-- ── Depositos ────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS warehouses (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id  uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name       text        NOT NULL CHECK (char_length(name) BETWEEN 2 AND 120),
  is_default boolean     NOT NULL DEFAULT false,
  is_active  boolean     NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid        REFERENCES auth.users(id),
  CONSTRAINT uq_warehouses_tenant_name UNIQUE (tenant_id, name)
);

-- No maximo um deposito padrao por tenant.
CREATE UNIQUE INDEX IF NOT EXISTS uq_warehouses_one_default
  ON warehouses (tenant_id) WHERE is_default;

CREATE INDEX IF NOT EXISTS idx_warehouses_tenant_active
  ON warehouses (tenant_id, is_active, name);

DROP TRIGGER IF EXISTS trg_warehouses_updated_at ON warehouses;
CREATE TRIGGER trg_warehouses_updated_at
  BEFORE UPDATE ON warehouses
  FOR EACH ROW EXECUTE FUNCTION _sf_update_updated_at();

-- ── Saldos (derivado) ────────────────────────────────────────────────────────
-- Fonte da verdade do custo: total_value_cents. O custo medio e derivado dele.

CREATE TABLE IF NOT EXISTS stock_balances (
  id               uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id        uuid          NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  warehouse_id     uuid          NOT NULL REFERENCES warehouses(id) ON DELETE CASCADE,
  product_id       uuid          NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  quantity         numeric(12,3) NOT NULL DEFAULT 0 CHECK (quantity >= 0),
  total_value_cents bigint       NOT NULL DEFAULT 0 CHECK (total_value_cents >= 0),
  updated_at       timestamptz   NOT NULL DEFAULT now(),
  CONSTRAINT uq_stock_balances_wh_product UNIQUE (warehouse_id, product_id)
);

CREATE INDEX IF NOT EXISTS idx_stock_balances_tenant
  ON stock_balances (tenant_id, product_id);

-- Custo medio para leitura. Nunca use isto para calcular baixa — a baixa usa
-- proporcao sobre total_value_cents, para nao arrastar erro de arredondamento.
CREATE OR REPLACE FUNCTION stock_average_unit_cost_cents(
  p_quantity numeric,
  p_total_value_cents bigint
) RETURNS integer LANGUAGE sql IMMUTABLE
AS $$
  SELECT CASE
           WHEN p_quantity IS NULL OR p_quantity <= 0 THEN 0
           ELSE round(p_total_value_cents::numeric / p_quantity)::integer
         END;
$$;

-- ── Movimentos (append-only) ─────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS stock_movements (
  id                 uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id          uuid          NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  warehouse_id       uuid          NOT NULL REFERENCES warehouses(id) ON DELETE CASCADE,
  product_id         uuid          NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  kind               text          NOT NULL CHECK (kind IN ('in','out','adjustment')),
  -- Sempre positiva. A direcao vem de kind, nao do sinal, para evitar
  -- ambiguidade em soma e em relatorio.
  quantity           numeric(12,3) NOT NULL CHECK (quantity > 0),
  unit_cost_cents    integer       NOT NULL DEFAULT 0 CHECK (unit_cost_cents >= 0),
  total_cost_cents   bigint        NOT NULL DEFAULT 0 CHECK (total_cost_cents >= 0),
  -- Saldo resultante, gravado no momento do movimento (invariante 3).
  quantity_after     numeric(12,3) NOT NULL CHECK (quantity_after >= 0),
  value_after_cents  bigint        NOT NULL CHECK (value_after_cents >= 0),
  reason             text          CHECK (reason IS NULL OR char_length(reason) <= 500),
  related_entity     text          CHECK (related_entity IS NULL OR char_length(related_entity) <= 60),
  related_entity_id  uuid,
  created_at         timestamptz   NOT NULL DEFAULT now(),
  created_by         uuid          REFERENCES auth.users(id)
);

CREATE INDEX IF NOT EXISTS idx_stock_movements_product
  ON stock_movements (warehouse_id, product_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_stock_movements_tenant
  ON stock_movements (tenant_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_stock_movements_related
  ON stock_movements (related_entity, related_entity_id)
  WHERE related_entity IS NOT NULL;

-- ── Permissoes ───────────────────────────────────────────────────────────────

INSERT INTO permissions (key, name, description) VALUES
  ('stock.read',   'Ler estoque',        'Consultar produtos, depositos, saldos e movimentos'),
  ('stock.write',  'Movimentar estoque', 'Registrar entradas e saidas; manter produtos e depositos'),
  ('stock.adjust', 'Ajustar estoque',    'Corrigir saldo por inventario — sobrepoe a contagem do sistema')
ON CONFLICT (key) DO NOTHING;

-- Backfill: o grant original de 0001 foi um cross join executado uma unica vez.
-- Permissoes criadas depois NAO chegam sozinhas aos papeis existentes.
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM   roles r, permissions p
WHERE  r.key = 'tenant_owner'
  AND  p.key IN ('stock.read','stock.write','stock.adjust')
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM   roles r, permissions p
WHERE  r.key = 'tenant_admin'
  AND  p.key IN ('stock.read','stock.write','stock.adjust')
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM   roles r, permissions p
WHERE  r.key = 'manager'
  AND  p.key IN ('stock.read','stock.write','stock.adjust')
ON CONFLICT DO NOTHING;

-- Tecnico consome material em campo, mas nao ajusta inventario.
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM   roles r, permissions p
WHERE  r.key = 'technician'
  AND  p.key IN ('stock.read','stock.write')
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM   roles r, permissions p
WHERE  r.key IN ('analyst','dispatcher','financial_operator','viewer')
  AND  p.key = 'stock.read'
ON CONFLICT DO NOTHING;

-- ── RLS ──────────────────────────────────────────────────────────────────────

ALTER TABLE products        ENABLE ROW LEVEL SECURITY;
ALTER TABLE warehouses      ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_balances  ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_movements ENABLE ROW LEVEL SECURITY;

-- Produtos e depositos: CRUD normal sob permissao.
DROP POLICY IF EXISTS "products_select" ON products;
CREATE POLICY "products_select" ON products
  FOR SELECT USING (tenant_id = current_tenant_id() AND has_permission('stock.read'));

DROP POLICY IF EXISTS "products_insert" ON products;
CREATE POLICY "products_insert" ON products
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id() AND has_permission('stock.write'));

DROP POLICY IF EXISTS "products_update" ON products;
CREATE POLICY "products_update" ON products
  FOR UPDATE USING (tenant_id = current_tenant_id() AND has_permission('stock.write'))
             WITH CHECK (tenant_id = current_tenant_id() AND has_permission('stock.write'));

DROP POLICY IF EXISTS "warehouses_select" ON warehouses;
CREATE POLICY "warehouses_select" ON warehouses
  FOR SELECT USING (tenant_id = current_tenant_id() AND has_permission('stock.read'));

DROP POLICY IF EXISTS "warehouses_insert" ON warehouses;
CREATE POLICY "warehouses_insert" ON warehouses
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id() AND has_permission('stock.write'));

DROP POLICY IF EXISTS "warehouses_update" ON warehouses;
CREATE POLICY "warehouses_update" ON warehouses
  FOR UPDATE USING (tenant_id = current_tenant_id() AND has_permission('stock.write'))
             WITH CHECK (tenant_id = current_tenant_id() AND has_permission('stock.write'));

-- Razao: leitura apenas. Sem DELETE em produto/deposito tambem, porque apagar
-- destroi historico de movimento; desative com is_active.
DROP POLICY IF EXISTS "stock_balances_select" ON stock_balances;
CREATE POLICY "stock_balances_select" ON stock_balances
  FOR SELECT USING (tenant_id = current_tenant_id() AND has_permission('stock.read'));

DROP POLICY IF EXISTS "stock_movements_select" ON stock_movements;
CREATE POLICY "stock_movements_select" ON stock_movements
  FOR SELECT USING (tenant_id = current_tenant_id() AND has_permission('stock.read'));

-- ── Helper interno: trava e devolve a linha de saldo, criando se faltar ──────

CREATE OR REPLACE FUNCTION _sf_lock_stock_balance(
  p_tenant_id    uuid,
  p_warehouse_id uuid,
  p_product_id   uuid
) RETURNS stock_balances LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_balance stock_balances;
BEGIN
  SELECT * INTO v_balance
  FROM stock_balances
  WHERE warehouse_id = p_warehouse_id AND product_id = p_product_id
  FOR UPDATE;

  IF NOT FOUND THEN
    INSERT INTO stock_balances (tenant_id, warehouse_id, product_id, quantity, total_value_cents)
    VALUES (p_tenant_id, p_warehouse_id, p_product_id, 0, 0)
    ON CONFLICT (warehouse_id, product_id) DO NOTHING;

    SELECT * INTO v_balance
    FROM stock_balances
    WHERE warehouse_id = p_warehouse_id AND product_id = p_product_id
    FOR UPDATE;
  END IF;

  RETURN v_balance;
END;
$$;

-- ── Helper interno: valida tenant, deposito e produto ────────────────────────

CREATE OR REPLACE FUNCTION _sf_validate_stock_target(
  p_tenant_id    uuid,
  p_warehouse_id uuid,
  p_product_id   uuid
) RETURNS void LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_ok boolean;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM warehouses
    WHERE id = p_warehouse_id AND tenant_id = p_tenant_id AND is_active
  ) INTO v_ok;
  IF NOT v_ok THEN
    RAISE EXCEPTION 'Deposito nao encontrado ou inativo.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM products
    WHERE id = p_product_id AND tenant_id = p_tenant_id AND is_active AND track_stock
  ) INTO v_ok;
  IF NOT v_ok THEN
    RAISE EXCEPTION 'Produto nao encontrado, inativo ou sem controle de estoque.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;
END;
$$;

-- ── RPC: entrada ─────────────────────────────────────────────────────────────
-- Custo medio ponderado movel (ADR-020): soma quantidade e soma valor.

CREATE OR REPLACE FUNCTION record_stock_entry(
  p_product_id       uuid,
  p_warehouse_id     uuid,
  p_quantity         numeric,
  p_unit_cost_cents  integer,
  p_reason           text DEFAULT NULL,
  p_related_entity   text DEFAULT NULL,
  p_related_entity_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id  uuid;
  v_balance    stock_balances;
  v_total_cost bigint;
  v_new_qty    numeric(12,3);
  v_new_value  bigint;
  v_movement_id uuid;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL OR NOT has_permission('stock.write') THEN
    RAISE EXCEPTION 'Permissao stock.write necessaria.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'Quantidade deve ser maior que zero.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF p_unit_cost_cents IS NULL OR p_unit_cost_cents < 0 THEN
    RAISE EXCEPTION 'Custo unitario invalido.'
      USING ERRCODE = 'check_violation';
  END IF;

  PERFORM _sf_validate_stock_target(v_tenant_id, p_warehouse_id, p_product_id);

  v_balance := _sf_lock_stock_balance(v_tenant_id, p_warehouse_id, p_product_id);

  v_total_cost := round(p_quantity * p_unit_cost_cents)::bigint;
  v_new_qty    := v_balance.quantity + p_quantity;
  v_new_value  := v_balance.total_value_cents + v_total_cost;

  UPDATE stock_balances
  SET quantity = v_new_qty,
      total_value_cents = v_new_value,
      updated_at = now()
  WHERE id = v_balance.id;

  INSERT INTO stock_movements (
    tenant_id, warehouse_id, product_id, kind, quantity,
    unit_cost_cents, total_cost_cents, quantity_after, value_after_cents,
    reason, related_entity, related_entity_id, created_by
  ) VALUES (
    v_tenant_id, p_warehouse_id, p_product_id, 'in', p_quantity,
    p_unit_cost_cents, v_total_cost, v_new_qty, v_new_value,
    p_reason, p_related_entity, p_related_entity_id, auth.uid()
  ) RETURNING id INTO v_movement_id;

  PERFORM log_audit(
    v_tenant_id, 'stock.entry', 'stock_movements', v_movement_id::text, NULL,
    jsonb_build_object(
      'product_id', p_product_id, 'warehouse_id', p_warehouse_id,
      'quantity', p_quantity, 'unit_cost_cents', p_unit_cost_cents
    )
  );

  RETURN jsonb_build_object(
    'movement_id', v_movement_id,
    'quantity', v_new_qty,
    'total_value_cents', v_new_value,
    'average_unit_cost_cents', stock_average_unit_cost_cents(v_new_qty, v_new_value)
  );
END;
$$;

-- ── RPC: saida ───────────────────────────────────────────────────────────────
-- Baixa proporcional sobre o valor total, nao pelo custo medio arredondado.
-- Isso evita que o residuo de arredondamento se acumule ou desapareca.

CREATE OR REPLACE FUNCTION record_stock_exit(
  p_product_id       uuid,
  p_warehouse_id     uuid,
  p_quantity         numeric,
  p_reason           text DEFAULT NULL,
  p_related_entity   text DEFAULT NULL,
  p_related_entity_id uuid DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id   uuid;
  v_balance     stock_balances;
  v_value_out   bigint;
  v_unit_cost   integer;
  v_new_qty     numeric(12,3);
  v_new_value   bigint;
  v_movement_id uuid;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL OR NOT has_permission('stock.write') THEN
    RAISE EXCEPTION 'Permissao stock.write necessaria.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_quantity IS NULL OR p_quantity <= 0 THEN
    RAISE EXCEPTION 'Quantidade deve ser maior que zero.'
      USING ERRCODE = 'check_violation';
  END IF;

  PERFORM _sf_validate_stock_target(v_tenant_id, p_warehouse_id, p_product_id);

  v_balance := _sf_lock_stock_balance(v_tenant_id, p_warehouse_id, p_product_id);

  -- Invariante 2: saldo nunca negativo.
  IF v_balance.quantity < p_quantity THEN
    RAISE EXCEPTION
      'Saldo insuficiente: disponivel %, solicitado %.', v_balance.quantity, p_quantity
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_balance.quantity = p_quantity THEN
    -- Zerou: leva todo o valor restante, inclusive o residuo de arredondamento.
    v_value_out := v_balance.total_value_cents;
  ELSE
    v_value_out := round(
      v_balance.total_value_cents::numeric * p_quantity / v_balance.quantity
    )::bigint;
  END IF;

  v_unit_cost := stock_average_unit_cost_cents(v_balance.quantity, v_balance.total_value_cents);
  v_new_qty   := v_balance.quantity - p_quantity;
  v_new_value := v_balance.total_value_cents - v_value_out;

  UPDATE stock_balances
  SET quantity = v_new_qty,
      total_value_cents = v_new_value,
      updated_at = now()
  WHERE id = v_balance.id;

  INSERT INTO stock_movements (
    tenant_id, warehouse_id, product_id, kind, quantity,
    unit_cost_cents, total_cost_cents, quantity_after, value_after_cents,
    reason, related_entity, related_entity_id, created_by
  ) VALUES (
    v_tenant_id, p_warehouse_id, p_product_id, 'out', p_quantity,
    v_unit_cost, v_value_out, v_new_qty, v_new_value,
    p_reason, p_related_entity, p_related_entity_id, auth.uid()
  ) RETURNING id INTO v_movement_id;

  PERFORM log_audit(
    v_tenant_id, 'stock.exit', 'stock_movements', v_movement_id::text, NULL,
    jsonb_build_object(
      'product_id', p_product_id, 'warehouse_id', p_warehouse_id,
      'quantity', p_quantity, 'value_out_cents', v_value_out
    )
  );

  RETURN jsonb_build_object(
    'movement_id', v_movement_id,
    'quantity', v_new_qty,
    'total_value_cents', v_new_value,
    'average_unit_cost_cents', stock_average_unit_cost_cents(v_new_qty, v_new_value)
  );
END;
$$;

-- ── RPC: ajuste de inventario ────────────────────────────────────────────────
-- Define a quantidade contada. Exige stock.adjust (mais restrito que write) e
-- motivo obrigatorio, porque sobrepoe o que o sistema calculou.

CREATE OR REPLACE FUNCTION record_stock_adjustment(
  p_product_id   uuid,
  p_warehouse_id uuid,
  p_new_quantity numeric,
  p_reason       text
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id   uuid;
  v_balance     stock_balances;
  v_unit_cost   integer;
  v_delta       numeric(12,3);
  v_new_value   bigint;
  v_movement_id uuid;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL OR NOT has_permission('stock.adjust') THEN
    RAISE EXCEPTION 'Permissao stock.adjust necessaria.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_new_quantity IS NULL OR p_new_quantity < 0 THEN
    RAISE EXCEPTION 'Quantidade contada invalida.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF p_reason IS NULL OR char_length(trim(p_reason)) < 3 THEN
    RAISE EXCEPTION 'Motivo do ajuste e obrigatorio.'
      USING ERRCODE = 'check_violation';
  END IF;

  PERFORM _sf_validate_stock_target(v_tenant_id, p_warehouse_id, p_product_id);

  v_balance := _sf_lock_stock_balance(v_tenant_id, p_warehouse_id, p_product_id);

  v_delta := p_new_quantity - v_balance.quantity;
  IF v_delta = 0 THEN
    RAISE EXCEPTION 'Quantidade contada igual ao saldo atual; nada a ajustar.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- O ajuste mantem o custo medio vigente: sobra ou falta de contagem nao muda
  -- o quanto o item custou. Se o saldo estava zerado, entra a custo zero e a
  -- valoracao correta vem na proxima entrada.
  v_unit_cost := stock_average_unit_cost_cents(v_balance.quantity, v_balance.total_value_cents);
  v_new_value := round(p_new_quantity * v_unit_cost)::bigint;

  UPDATE stock_balances
  SET quantity = p_new_quantity,
      total_value_cents = v_new_value,
      updated_at = now()
  WHERE id = v_balance.id;

  INSERT INTO stock_movements (
    tenant_id, warehouse_id, product_id, kind, quantity,
    unit_cost_cents, total_cost_cents, quantity_after, value_after_cents,
    reason, created_by
  ) VALUES (
    v_tenant_id, p_warehouse_id, p_product_id, 'adjustment', abs(v_delta),
    v_unit_cost, round(abs(v_delta) * v_unit_cost)::bigint, p_new_quantity, v_new_value,
    p_reason, auth.uid()
  ) RETURNING id INTO v_movement_id;

  PERFORM log_audit(
    v_tenant_id, 'stock.adjustment', 'stock_movements', v_movement_id::text, NULL,
    jsonb_build_object(
      'product_id', p_product_id, 'warehouse_id', p_warehouse_id,
      'previous_quantity', v_balance.quantity, 'new_quantity', p_new_quantity,
      'delta', v_delta, 'reason', p_reason
    )
  );

  RETURN jsonb_build_object(
    'movement_id', v_movement_id,
    'quantity', p_new_quantity,
    'total_value_cents', v_new_value,
    'average_unit_cost_cents', stock_average_unit_cost_cents(p_new_quantity, v_new_value)
  );
END;
$$;

-- ── RPC: leitura de saldos com dados do produto ──────────────────────────────

CREATE OR REPLACE FUNCTION list_stock_balances(
  p_warehouse_id uuid DEFAULT NULL,
  p_only_below_min boolean DEFAULT false
)
RETURNS TABLE (
  product_id              uuid,
  product_name            text,
  sku                     text,
  unit                    text,
  warehouse_id            uuid,
  warehouse_name          text,
  quantity                numeric,
  min_quantity            numeric,
  total_value_cents       bigint,
  average_unit_cost_cents integer,
  below_minimum           boolean,
  updated_at              timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL OR NOT has_permission('stock.read') THEN
    RAISE EXCEPTION 'Permissao stock.read necessaria.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  RETURN QUERY
  SELECT
    p.id, p.name, p.sku, p.unit,
    w.id, w.name,
    b.quantity, p.min_quantity,
    b.total_value_cents,
    stock_average_unit_cost_cents(b.quantity, b.total_value_cents),
    (p.min_quantity > 0 AND b.quantity < p.min_quantity),
    b.updated_at
  FROM stock_balances b
  JOIN products   p ON p.id = b.product_id
  JOIN warehouses w ON w.id = b.warehouse_id
  WHERE b.tenant_id = v_tenant_id
    AND (p_warehouse_id IS NULL OR b.warehouse_id = p_warehouse_id)
    AND (NOT p_only_below_min OR (p.min_quantity > 0 AND b.quantity < p.min_quantity))
  ORDER BY p.name, w.name;
END;
$$;

COMMENT ON TABLE stock_movements IS
  'Razao de estoque append-only. Nunca alterar nem apagar: corrija com movimento contrario.';
COMMENT ON TABLE stock_balances IS
  'Saldo derivado. total_value_cents e a fonte da verdade do custo; o medio e calculado a partir dele (ADR-020).';
COMMENT ON FUNCTION stock_average_unit_cost_cents IS
  'Custo medio para exibicao. Nao use para calcular baixa — a baixa e proporcional ao valor total.';

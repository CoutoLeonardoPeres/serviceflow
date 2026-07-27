-- =============================================================================
-- Migration: 0044_suppliers_purchase_orders
-- Descricao: Fornecedores e pedidos de compra com recebimento — F3-P3
-- Depende de: 0001_foundation, 0042_stock_ledger
-- Rollback: supabase/rollbacks/0044_suppliers_purchase_orders_rollback.sql
--
-- FRONTEIRA COM O FINANCEIRO:
--   O pedido registra o custo, mas NAO gera conta a pagar — `payables` nao
--   existe ainda (previsto para F4). Ligar compra a contas a pagar e escopo
--   de F4; ate la, o custo entra no estoque e o financeiro do pedido fica
--   fora do sistema.
--
-- QUEM MOVIMENTA O ESTOQUE:
--   O pedido em si nao mexe em saldo. Somente o RECEBIMENTO gera entrada, via
--   record_stock_entry, com o custo real da nota. Isso importa: se o preco
--   mudou entre o pedido e a entrega, o custo medio reflete o que foi pago,
--   nao o que foi cotado.
--
-- CICLO:
--   draft -> sent -> partially_received -> received
--   draft/sent -> cancelled
--   Recebido nao volta atras: correcao se faz por ajuste de inventario, que ja
--   exige stock.adjust e motivo (0042). Assim o razao continua append-only e
--   auditavel.
-- =============================================================================

-- ── Fornecedores ─────────────────────────────────────────────────────────────
-- Tabela propria em vez de reaproveitar `customers`: o cadastro de parceiros
-- unificado esta previsto para F5, e forcar a unificacao agora acoplaria dois
-- modulos que ainda vao mudar.

CREATE TABLE IF NOT EXISTS suppliers (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name        text        NOT NULL CHECK (char_length(name) BETWEEN 2 AND 200),
  trade_name  text        CHECK (trade_name IS NULL OR char_length(trade_name) <= 200),
  document    text        CHECK (document IS NULL OR char_length(document) <= 20),
  email       text        CHECK (email IS NULL OR char_length(email) <= 160),
  phone       text        CHECK (phone IS NULL OR char_length(phone) <= 20),
  notes       text        CHECK (notes IS NULL OR char_length(notes) <= 1000),
  is_active   boolean     NOT NULL DEFAULT true,
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now(),
  created_by  uuid        REFERENCES auth.users(id),
  CONSTRAINT uq_suppliers_tenant_document UNIQUE (tenant_id, document)
);

CREATE INDEX IF NOT EXISTS idx_suppliers_tenant_active
  ON suppliers (tenant_id, is_active, name);

DROP TRIGGER IF EXISTS trg_suppliers_updated_at ON suppliers;
CREATE TRIGGER trg_suppliers_updated_at
  BEFORE UPDATE ON suppliers
  FOR EACH ROW EXECUTE FUNCTION _sf_update_updated_at();

-- ── Pedidos de compra ────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS purchase_orders (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id       uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  number          bigint      NOT NULL,
  supplier_id     uuid        NOT NULL REFERENCES suppliers(id),
  warehouse_id    uuid        NOT NULL REFERENCES warehouses(id),
  status          text        NOT NULL DEFAULT 'draft'
                              CHECK (status IN ('draft','sent','partially_received','received','cancelled')),
  expected_at     date,
  notes           text        CHECK (notes IS NULL OR char_length(notes) <= 1000),
  total_cents     bigint      NOT NULL DEFAULT 0 CHECK (total_cents >= 0),
  sent_at         timestamptz,
  received_at     timestamptz,
  cancelled_at    timestamptz,
  cancellation_reason text    CHECK (cancellation_reason IS NULL OR char_length(cancellation_reason) <= 500),
  created_at      timestamptz NOT NULL DEFAULT now(),
  updated_at      timestamptz NOT NULL DEFAULT now(),
  created_by      uuid        REFERENCES auth.users(id),
  CONSTRAINT uq_purchase_orders_tenant_number UNIQUE (tenant_id, number)
);

CREATE INDEX IF NOT EXISTS idx_purchase_orders_tenant_status
  ON purchase_orders (tenant_id, status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_purchase_orders_supplier
  ON purchase_orders (supplier_id);

DROP TRIGGER IF EXISTS trg_purchase_orders_updated_at ON purchase_orders;
CREATE TRIGGER trg_purchase_orders_updated_at
  BEFORE UPDATE ON purchase_orders
  FOR EACH ROW EXECUTE FUNCTION _sf_update_updated_at();

CREATE TABLE IF NOT EXISTS purchase_order_items (
  id                uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id         uuid          NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  purchase_order_id uuid          NOT NULL REFERENCES purchase_orders(id) ON DELETE CASCADE,
  product_id        uuid          NOT NULL REFERENCES products(id),
  quantity_ordered  numeric(12,3) NOT NULL CHECK (quantity_ordered > 0),
  -- Nunca pode passar do pedido: receber a mais e erro de conferencia, e
  -- deixar passar mascararia divergencia com o fornecedor.
  quantity_received numeric(12,3) NOT NULL DEFAULT 0 CHECK (quantity_received >= 0),
  unit_cost_cents   integer       NOT NULL CHECK (unit_cost_cents >= 0),
  created_at        timestamptz   NOT NULL DEFAULT now(),
  CONSTRAINT ck_purchase_item_not_over_received
    CHECK (quantity_received <= quantity_ordered)
);

CREATE INDEX IF NOT EXISTS idx_purchase_order_items_order
  ON purchase_order_items (purchase_order_id);
CREATE INDEX IF NOT EXISTS idx_purchase_order_items_product
  ON purchase_order_items (product_id);

-- ── Permissoes ───────────────────────────────────────────────────────────────

INSERT INTO permissions (key, name, description) VALUES
  ('purchases.read',  'Ler compras',      'Consultar fornecedores e pedidos de compra'),
  ('purchases.write', 'Gerenciar compras','Criar e enviar pedidos; manter fornecedores'),
  ('purchases.receive','Receber compras', 'Registrar recebimento, gerando entrada no estoque')
ON CONFLICT (key) DO NOTHING;

-- Backfill obrigatorio: o grant de 0001 foi um cross join executado uma vez.
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM   roles r, permissions p
WHERE  r.key IN ('tenant_owner','tenant_admin','manager')
  AND  p.key IN ('purchases.read','purchases.write','purchases.receive')
ON CONFLICT DO NOTHING;

-- Tecnico e almoxarife recebem mercadoria, mas nao emitem pedido.
--
-- ACOPLAMENTO IMPORTANTE: receber exige purchases.receive E stock.write, porque
-- receive_purchase_order chama record_stock_entry, que checa stock.write por
-- conta propria. Todos os papeis abaixo ja tem stock.write de 0042. Se um papel
-- novo ganhar purchases.receive sem stock.write, o recebimento falha com a
-- mensagem de estoque, que nao explica a causa real.
INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM   roles r, permissions p
WHERE  r.key = 'technician'
  AND  p.key IN ('purchases.read','purchases.receive')
ON CONFLICT DO NOTHING;

INSERT INTO role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM   roles r, permissions p
WHERE  r.key IN ('analyst','dispatcher','financial_operator','viewer')
  AND  p.key = 'purchases.read'
ON CONFLICT DO NOTHING;

-- ── RLS ──────────────────────────────────────────────────────────────────────

ALTER TABLE suppliers            ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_orders      ENABLE ROW LEVEL SECURITY;
ALTER TABLE purchase_order_items ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "suppliers_select" ON suppliers;
CREATE POLICY "suppliers_select" ON suppliers
  FOR SELECT USING (tenant_id = current_tenant_id() AND has_permission('purchases.read'));

DROP POLICY IF EXISTS "suppliers_insert" ON suppliers;
CREATE POLICY "suppliers_insert" ON suppliers
  FOR INSERT WITH CHECK (tenant_id = current_tenant_id() AND has_permission('purchases.write'));

DROP POLICY IF EXISTS "suppliers_update" ON suppliers;
CREATE POLICY "suppliers_update" ON suppliers
  FOR UPDATE USING (tenant_id = current_tenant_id() AND has_permission('purchases.write'))
             WITH CHECK (tenant_id = current_tenant_id() AND has_permission('purchases.write'));

-- Pedidos e itens: leitura direta; toda mutacao passa pelos RPCs, para que o
-- ciclo de status e o vinculo com o estoque nao possam ser burlados.
DROP POLICY IF EXISTS "purchase_orders_select" ON purchase_orders;
CREATE POLICY "purchase_orders_select" ON purchase_orders
  FOR SELECT USING (tenant_id = current_tenant_id() AND has_permission('purchases.read'));

DROP POLICY IF EXISTS "purchase_order_items_select" ON purchase_order_items;
CREATE POLICY "purchase_order_items_select" ON purchase_order_items
  FOR SELECT USING (tenant_id = current_tenant_id() AND has_permission('purchases.read'));

-- ── RPC: criar pedido ────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION create_purchase_order(
  p_supplier_id  uuid,
  p_warehouse_id uuid,
  p_items        jsonb,
  p_expected_at  date DEFAULT NULL,
  p_notes        text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_order_id  uuid;
  v_number    bigint;
  v_item      jsonb;
  v_total     bigint := 0;
  v_qty       numeric;
  v_cost      integer;
  v_ok        boolean;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL OR NOT has_permission('purchases.write') THEN
    RAISE EXCEPTION 'Permissao purchases.write necessaria.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM suppliers
    WHERE id = p_supplier_id AND tenant_id = v_tenant_id AND is_active
  ) INTO v_ok;
  IF NOT v_ok THEN
    RAISE EXCEPTION 'Fornecedor nao encontrado ou inativo.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT EXISTS (
    SELECT 1 FROM warehouses
    WHERE id = p_warehouse_id AND tenant_id = v_tenant_id AND is_active
  ) INTO v_ok;
  IF NOT v_ok THEN
    RAISE EXCEPTION 'Deposito nao encontrado ou inativo.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Pedido precisa de ao menos um item.'
      USING ERRCODE = 'check_violation';
  END IF;

  v_number := next_sequence(v_tenant_id, 'purchase_order');

  INSERT INTO purchase_orders (
    tenant_id, number, supplier_id, warehouse_id, status,
    expected_at, notes, created_by
  ) VALUES (
    v_tenant_id, v_number, p_supplier_id, p_warehouse_id, 'draft',
    p_expected_at, p_notes, auth.uid()
  ) RETURNING id INTO v_order_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_qty  := (v_item->>'quantity')::numeric;
    v_cost := (v_item->>'unit_cost_cents')::integer;

    IF v_qty IS NULL OR v_qty <= 0 THEN
      RAISE EXCEPTION 'Quantidade invalida no item do pedido.'
        USING ERRCODE = 'check_violation';
    END IF;

    IF v_cost IS NULL OR v_cost < 0 THEN
      RAISE EXCEPTION 'Custo invalido no item do pedido.'
        USING ERRCODE = 'check_violation';
    END IF;

    SELECT EXISTS (
      SELECT 1 FROM products
      WHERE id = (v_item->>'product_id')::uuid
        AND tenant_id = v_tenant_id AND is_active
    ) INTO v_ok;
    IF NOT v_ok THEN
      RAISE EXCEPTION 'Produto do item nao encontrado ou inativo.'
        USING ERRCODE = 'insufficient_privilege';
    END IF;

    INSERT INTO purchase_order_items (
      tenant_id, purchase_order_id, product_id, quantity_ordered, unit_cost_cents
    ) VALUES (
      v_tenant_id, v_order_id, (v_item->>'product_id')::uuid, v_qty, v_cost
    );

    v_total := v_total + round(v_qty * v_cost)::bigint;
  END LOOP;

  UPDATE purchase_orders SET total_cents = v_total WHERE id = v_order_id;

  PERFORM log_audit(
    v_tenant_id, 'purchase_order.created', 'purchase_orders', v_order_id::text,
    NULL, jsonb_build_object('number', v_number, 'total_cents', v_total)
  );

  RETURN jsonb_build_object(
    'id', v_order_id, 'number', v_number, 'total_cents', v_total
  );
END;
$$;

-- ── RPC: enviar pedido ───────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION send_purchase_order(p_order_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_status    text;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL OR NOT has_permission('purchases.write') THEN
    RAISE EXCEPTION 'Permissao purchases.write necessaria.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT status INTO v_status
  FROM purchase_orders
  WHERE id = p_order_id AND tenant_id = v_tenant_id;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Pedido nao encontrado.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_status <> 'draft' THEN
    RAISE EXCEPTION 'Somente pedido em rascunho pode ser enviado.'
      USING ERRCODE = 'check_violation';
  END IF;

  UPDATE purchase_orders
  SET status = 'sent', sent_at = now()
  WHERE id = p_order_id;

  PERFORM log_audit(
    v_tenant_id, 'purchase_order.sent', 'purchase_orders', p_order_id::text,
    NULL, jsonb_build_object()
  );
END;
$$;

-- ── RPC: receber (total ou parcial) ──────────────────────────────────────────
--
-- p_items: [{ "item_id": uuid, "quantity": numeric, "unit_cost_cents": int? }]
-- unit_cost_cents e opcional: se a nota veio com preco diferente do pedido,
-- vale o da nota — e ele que entra no custo medio.

CREATE OR REPLACE FUNCTION receive_purchase_order(
  p_order_id uuid,
  p_items    jsonb
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id   uuid;
  v_order       purchase_orders;
  v_item        jsonb;
  v_po_item     purchase_order_items;
  v_qty         numeric;
  v_cost        integer;
  v_received    int := 0;
  v_all_done    boolean;
  v_new_status  text;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL OR NOT has_permission('purchases.receive') THEN
    RAISE EXCEPTION 'Permissao purchases.receive necessaria.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_order
  FROM purchase_orders
  WHERE id = p_order_id AND tenant_id = v_tenant_id
  FOR UPDATE;

  IF v_order.id IS NULL THEN
    RAISE EXCEPTION 'Pedido nao encontrado.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_order.status NOT IN ('sent','partially_received') THEN
    RAISE EXCEPTION
      'Pedido com status "%" nao aceita recebimento.', v_order.status
      USING ERRCODE = 'check_violation';
  END IF;

  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Informe ao menos um item recebido.'
      USING ERRCODE = 'check_violation';
  END IF;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    SELECT * INTO v_po_item
    FROM purchase_order_items
    WHERE id = (v_item->>'item_id')::uuid
      AND purchase_order_id = p_order_id
    FOR UPDATE;

    IF v_po_item.id IS NULL THEN
      RAISE EXCEPTION 'Item do pedido nao encontrado.'
        USING ERRCODE = 'insufficient_privilege';
    END IF;

    v_qty := (v_item->>'quantity')::numeric;
    IF v_qty IS NULL OR v_qty <= 0 THEN
      RAISE EXCEPTION 'Quantidade recebida invalida.'
        USING ERRCODE = 'check_violation';
    END IF;

    IF v_po_item.quantity_received + v_qty > v_po_item.quantity_ordered THEN
      RAISE EXCEPTION
        'Recebimento acima do pedido: pedido %, ja recebido %, tentando receber %.',
        v_po_item.quantity_ordered, v_po_item.quantity_received, v_qty
        USING ERRCODE = 'check_violation';
    END IF;

    -- Preco da nota prevalece sobre o cotado, quando informado.
    v_cost := COALESCE(
      (v_item->>'unit_cost_cents')::integer,
      v_po_item.unit_cost_cents
    );
    IF v_cost < 0 THEN
      RAISE EXCEPTION 'Custo recebido invalido.'
        USING ERRCODE = 'check_violation';
    END IF;

    -- E aqui que o estoque entra. Se isto falhar, a transacao inteira volta e
    -- o pedido nao fica marcado como recebido.
    PERFORM record_stock_entry(
      p_product_id       => v_po_item.product_id,
      p_warehouse_id     => v_order.warehouse_id,
      p_quantity         => v_qty,
      p_unit_cost_cents  => v_cost,
      p_reason           => 'Recebimento do pedido #' || v_order.number::text,
      p_related_entity   => 'purchase_orders',
      p_related_entity_id => p_order_id
    );

    UPDATE purchase_order_items
    SET quantity_received = quantity_received + v_qty
    WHERE id = v_po_item.id;

    v_received := v_received + 1;
  END LOOP;

  SELECT bool_and(quantity_received >= quantity_ordered) INTO v_all_done
  FROM purchase_order_items
  WHERE purchase_order_id = p_order_id;

  v_new_status := CASE WHEN v_all_done THEN 'received' ELSE 'partially_received' END;

  UPDATE purchase_orders
  SET status = v_new_status,
      received_at = CASE WHEN v_all_done THEN now() ELSE received_at END
  WHERE id = p_order_id;

  PERFORM log_audit(
    v_tenant_id, 'purchase_order.received', 'purchase_orders', p_order_id::text,
    NULL,
    jsonb_build_object(
      'items_received', v_received,
      'status', v_new_status,
      'fully_received', v_all_done
    )
  );

  RETURN jsonb_build_object(
    'status', v_new_status,
    'fully_received', v_all_done,
    'items_received', v_received
  );
END;
$$;

-- ── RPC: cancelar pedido ─────────────────────────────────────────────────────
-- Pedido com recebimento parcial nao pode ser cancelado: o estoque ja entrou.
-- Cancelar apagaria o rastro de uma mercadoria que existe fisicamente.

CREATE OR REPLACE FUNCTION cancel_purchase_order(
  p_order_id uuid,
  p_reason   text
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_status    text;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL OR NOT has_permission('purchases.write') THEN
    RAISE EXCEPTION 'Permissao purchases.write necessaria.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_reason IS NULL OR char_length(trim(p_reason)) < 3 THEN
    RAISE EXCEPTION 'Motivo do cancelamento e obrigatorio.'
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT status INTO v_status
  FROM purchase_orders
  WHERE id = p_order_id AND tenant_id = v_tenant_id;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Pedido nao encontrado.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_status NOT IN ('draft','sent') THEN
    RAISE EXCEPTION
      'Pedido com status "%" nao pode ser cancelado. Mercadoria ja recebida se corrige por ajuste de inventario.',
      v_status
      USING ERRCODE = 'check_violation';
  END IF;

  UPDATE purchase_orders
  SET status = 'cancelled',
      cancelled_at = now(),
      cancellation_reason = trim(p_reason)
  WHERE id = p_order_id;

  PERFORM log_audit(
    v_tenant_id, 'purchase_order.cancelled', 'purchase_orders', p_order_id::text,
    NULL, jsonb_build_object('reason', trim(p_reason))
  );
END;
$$;

-- ── RPC: listar itens com pendencia ──────────────────────────────────────────

CREATE OR REPLACE FUNCTION list_purchase_order_items(p_order_id uuid)
RETURNS TABLE (
  id                uuid,
  product_id        uuid,
  product_name      text,
  sku               text,
  unit              text,
  quantity_ordered  numeric,
  quantity_received numeric,
  quantity_pending  numeric,
  unit_cost_cents   integer,
  total_cost_cents  bigint
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL OR NOT has_permission('purchases.read') THEN
    RAISE EXCEPTION 'Permissao purchases.read necessaria.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  RETURN QUERY
  SELECT
    i.id, i.product_id, p.name, p.sku, p.unit,
    i.quantity_ordered, i.quantity_received,
    i.quantity_ordered - i.quantity_received,
    i.unit_cost_cents,
    round(i.quantity_ordered * i.unit_cost_cents)::bigint
  FROM purchase_order_items i
  JOIN products p ON p.id = i.product_id
  WHERE i.purchase_order_id = p_order_id
    AND i.tenant_id = v_tenant_id
  ORDER BY p.name;
END;
$$;

COMMENT ON TABLE purchase_orders IS
  'Pedido de compra. Nao movimenta estoque: somente o recebimento gera entrada, com o custo real da nota (F3-P3).';
COMMENT ON COLUMN purchase_order_items.quantity_received IS
  'Acumulado recebido. CHECK impede ultrapassar o pedido — receber a mais e erro de conferencia.';

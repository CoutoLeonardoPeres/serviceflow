-- =============================================================================
-- 0047_stock_lot_serial_tracking.sql — F3-P5
--
-- Rastreabilidade opcional por lote/série (ADR-024). Um produto escolhe UM
-- tipo de rastreio: 'none' (padrão, maioria dos produtos), 'lot' (lote de
-- fabricação compartilhado) ou 'serial' (identidade única por unidade, cada
-- movimento limitado a quantidade = 1). Sem data de validade — só
-- identificação e rastreabilidade (qual lote/série saiu em qual OS).
--
-- Fora de escopo (ver ADR-024): transferências entre depósitos
-- (transfer_stock insere direto em stock_movements, não passa por
-- record_stock_exit/entry) e inventário cíclico (stock_counts ajusta o
-- agregado do produto, não lotes individuais) não carregam lote/série nesta
-- entrega.
--
-- ATENÇÃO — armadilha de aridade (já documentada em supabase/rollbacks/README.md):
-- CREATE OR REPLACE com parâmetro novo no final, mesmo com DEFAULT, NÃO
-- substitui a função — cria uma sobrecarga. DROP FUNCTION da assinatura
-- exata antes de cada CREATE OR REPLACE abaixo, para record_stock_entry,
-- record_stock_exit, record_stock_adjustment e add_work_order_material.
-- =============================================================================

ALTER TABLE products
  ADD COLUMN IF NOT EXISTS tracking_type text NOT NULL DEFAULT 'none'
    CHECK (tracking_type IN ('none', 'lot', 'serial'));

CREATE TABLE IF NOT EXISTS stock_lots (
  id         uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id  uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  product_id uuid        NOT NULL REFERENCES products(id) ON DELETE CASCADE,
  code       text        NOT NULL CHECK (char_length(code) BETWEEN 1 AND 80),
  created_at timestamptz NOT NULL DEFAULT now(),
  created_by uuid        REFERENCES auth.users(id),
  CONSTRAINT uq_stock_lots_tenant_product_code UNIQUE (tenant_id, product_id, code)
);
-- Unicidade case-insensitive (a UNIQUE acima é case-sensitive; complementada
-- por indice funcional, mesmo padrão de products_tenant_lower_name em 0002).
CREATE UNIQUE INDEX IF NOT EXISTS uq_stock_lots_tenant_product_lower_code
  ON stock_lots (tenant_id, product_id, lower(code));
CREATE INDEX IF NOT EXISTS idx_stock_lots_product ON stock_lots(product_id);

ALTER TABLE stock_movements ADD COLUMN IF NOT EXISTS lot_id uuid REFERENCES stock_lots(id);
CREATE INDEX IF NOT EXISTS idx_stock_movements_lot ON stock_movements(lot_id) WHERE lot_id IS NOT NULL;

ALTER TABLE stock_lots ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "stock_lots_select" ON stock_lots;
CREATE POLICY "stock_lots_select" ON stock_lots
  FOR SELECT USING (tenant_id = current_tenant_id() AND has_permission('stock.read'));

-- ── Helper interno: resolve (ou cria) o lote/série e valida as regras dele ──
--
-- Não é SECURITY DEFINER — mesmo padrão de _sf_lock_stock_balance e
-- _sf_validate_stock_target: só é chamada de dentro de funções que já são
-- SECURITY DEFINER, e herda o contexto de privilégio delas.

CREATE OR REPLACE FUNCTION _sf_resolve_stock_lot(
  p_tenant_id  uuid,
  p_product_id uuid,
  p_quantity   numeric,
  p_lot_code   text,
  p_for_entry  boolean
) RETURNS uuid LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  v_tracking  text;
  v_lot_id    uuid;
  v_last_kind text;
  v_code      text;
BEGIN
  SELECT tracking_type INTO v_tracking FROM products WHERE id = p_product_id;

  IF v_tracking IS NULL OR v_tracking = 'none' THEN
    RETURN NULL;
  END IF;

  v_code := trim(coalesce(p_lot_code, ''));
  IF v_code = '' THEN
    RAISE EXCEPTION 'Produto exige informar %.',
      CASE WHEN v_tracking = 'serial' THEN 'numero de serie' ELSE 'lote' END
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_tracking = 'serial' AND p_quantity <> 1 THEN
    RAISE EXCEPTION 'Produto com numero de serie aceita apenas 1 unidade por movimento.'
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT id INTO v_lot_id
  FROM stock_lots
  WHERE tenant_id = p_tenant_id AND product_id = p_product_id AND lower(code) = lower(v_code);

  IF v_lot_id IS NULL THEN
    IF NOT p_for_entry THEN
      RAISE EXCEPTION 'Lote/numero de serie "%" nao encontrado.', v_code
        USING ERRCODE = 'check_violation';
    END IF;

    INSERT INTO stock_lots (tenant_id, product_id, code, created_by)
    VALUES (p_tenant_id, p_product_id, v_code, auth.uid())
    RETURNING id INTO v_lot_id;

    RETURN v_lot_id;
  END IF;

  -- Numero de serie: so pode ter uma "posse" por vez (evita entrada duplicada
  -- de uma serie ja em estoque, ou saida de uma serie ja consumida/nao
  -- entrada). Olha o ultimo movimento desse lote_id em qualquer deposito.
  IF v_tracking = 'serial' THEN
    SELECT kind INTO v_last_kind
    FROM stock_movements
    WHERE lot_id = v_lot_id
    ORDER BY created_at DESC
    LIMIT 1;

    IF p_for_entry THEN
      IF v_last_kind = 'in' THEN
        RAISE EXCEPTION 'Numero de serie "%" ja esta em estoque.', v_code
          USING ERRCODE = 'check_violation';
      END IF;
    ELSE
      IF v_last_kind IS DISTINCT FROM 'in' THEN
        RAISE EXCEPTION 'Numero de serie "%" nao esta disponivel para saida.', v_code
          USING ERRCODE = 'check_violation';
      END IF;
    END IF;
  END IF;

  RETURN v_lot_id;
END;
$$;

-- ── record_stock_entry: +p_lot_code ─────────────────────────────────────────

DROP FUNCTION IF EXISTS record_stock_entry(uuid, uuid, numeric, integer, text, text, uuid);

CREATE OR REPLACE FUNCTION record_stock_entry(
  p_product_id       uuid,
  p_warehouse_id     uuid,
  p_quantity         numeric,
  p_unit_cost_cents  integer,
  p_reason           text DEFAULT NULL,
  p_related_entity   text DEFAULT NULL,
  p_related_entity_id uuid DEFAULT NULL,
  p_lot_code         text DEFAULT NULL
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
  v_lot_id     uuid;
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

  v_lot_id := _sf_resolve_stock_lot(v_tenant_id, p_product_id, p_quantity, p_lot_code, true);

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
    reason, related_entity, related_entity_id, created_by, lot_id
  ) VALUES (
    v_tenant_id, p_warehouse_id, p_product_id, 'in', p_quantity,
    p_unit_cost_cents, v_total_cost, v_new_qty, v_new_value,
    p_reason, p_related_entity, p_related_entity_id, auth.uid(), v_lot_id
  ) RETURNING id INTO v_movement_id;

  PERFORM log_audit(
    v_tenant_id, 'stock.entry', 'stock_movements', v_movement_id::text, NULL,
    jsonb_build_object(
      'product_id', p_product_id, 'warehouse_id', p_warehouse_id,
      'quantity', p_quantity, 'unit_cost_cents', p_unit_cost_cents,
      'lot_id', v_lot_id
    )
  );

  RETURN jsonb_build_object(
    'movement_id', v_movement_id,
    'quantity', v_new_qty,
    'total_value_cents', v_new_value,
    'average_unit_cost_cents', stock_average_unit_cost_cents(v_new_qty, v_new_value),
    'lot_id', v_lot_id
  );
END;
$$;

-- ── record_stock_exit: +p_lot_code ──────────────────────────────────────────

DROP FUNCTION IF EXISTS record_stock_exit(uuid, uuid, numeric, text, text, uuid);

CREATE OR REPLACE FUNCTION record_stock_exit(
  p_product_id       uuid,
  p_warehouse_id     uuid,
  p_quantity         numeric,
  p_reason           text DEFAULT NULL,
  p_related_entity   text DEFAULT NULL,
  p_related_entity_id uuid DEFAULT NULL,
  p_lot_code         text DEFAULT NULL
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
  v_lot_id      uuid;
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

  -- Resolve o lote ANTES de travar/alterar o saldo: se a serie/lote for
  -- invalido, nada foi escrito ainda.
  v_lot_id := _sf_resolve_stock_lot(v_tenant_id, p_product_id, p_quantity, p_lot_code, false);

  v_balance := _sf_lock_stock_balance(v_tenant_id, p_warehouse_id, p_product_id);

  -- Invariante 2: saldo nunca negativo.
  IF v_balance.quantity < p_quantity THEN
    RAISE EXCEPTION
      'Saldo insuficiente: disponivel %, solicitado %.', v_balance.quantity, p_quantity
      USING ERRCODE = 'check_violation';
  END IF;

  IF v_balance.quantity = p_quantity THEN
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
    reason, related_entity, related_entity_id, created_by, lot_id
  ) VALUES (
    v_tenant_id, p_warehouse_id, p_product_id, 'out', p_quantity,
    v_unit_cost, v_value_out, v_new_qty, v_new_value,
    p_reason, p_related_entity, p_related_entity_id, auth.uid(), v_lot_id
  ) RETURNING id INTO v_movement_id;

  PERFORM log_audit(
    v_tenant_id, 'stock.exit', 'stock_movements', v_movement_id::text, NULL,
    jsonb_build_object(
      'product_id', p_product_id, 'warehouse_id', p_warehouse_id,
      'quantity', p_quantity, 'value_out_cents', v_value_out, 'lot_id', v_lot_id
    )
  );

  RETURN jsonb_build_object(
    'movement_id', v_movement_id,
    'quantity', v_new_qty,
    'total_value_cents', v_new_value,
    'average_unit_cost_cents', stock_average_unit_cost_cents(v_new_qty, v_new_value),
    'lot_id', v_lot_id
  );
END;
$$;

-- ── record_stock_adjustment: +p_lot_code (opcional, sem enforcement) ────────
-- Contagem cíclica (stock_counts) ajusta o agregado do produto, não lotes
-- individuais — ver ADR-024. Aqui o lote é só uma etiqueta opcional no
-- movimento se o chamador passar um; não é exigido mesmo para produtos com
-- tracking_type != 'none'. Lacuna conhecida, não redesenha stock_counts.

DROP FUNCTION IF EXISTS record_stock_adjustment(uuid, uuid, numeric, text);

CREATE OR REPLACE FUNCTION record_stock_adjustment(
  p_product_id   uuid,
  p_warehouse_id uuid,
  p_new_quantity numeric,
  p_reason       text,
  p_lot_code     text DEFAULT NULL
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
  v_lot_id      uuid;
  v_code        text;
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

  v_code := trim(coalesce(p_lot_code, ''));
  IF v_code <> '' THEN
    SELECT id INTO v_lot_id
    FROM stock_lots
    WHERE tenant_id = v_tenant_id AND product_id = p_product_id AND lower(code) = lower(v_code);

    IF v_lot_id IS NULL THEN
      INSERT INTO stock_lots (tenant_id, product_id, code, created_by)
      VALUES (v_tenant_id, p_product_id, v_code, auth.uid())
      RETURNING id INTO v_lot_id;
    END IF;
  END IF;

  v_balance := _sf_lock_stock_balance(v_tenant_id, p_warehouse_id, p_product_id);

  v_delta := p_new_quantity - v_balance.quantity;
  IF v_delta = 0 THEN
    RAISE EXCEPTION 'Quantidade contada igual ao saldo atual; nada a ajustar.'
      USING ERRCODE = 'check_violation';
  END IF;

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
    reason, created_by, lot_id
  ) VALUES (
    v_tenant_id, p_warehouse_id, p_product_id, 'adjustment', abs(v_delta),
    v_unit_cost, round(abs(v_delta) * v_unit_cost)::bigint, p_new_quantity, v_new_value,
    p_reason, auth.uid(), v_lot_id
  ) RETURNING id INTO v_movement_id;

  PERFORM log_audit(
    v_tenant_id, 'stock.adjustment', 'stock_movements', v_movement_id::text, NULL,
    jsonb_build_object(
      'product_id', p_product_id, 'warehouse_id', p_warehouse_id,
      'previous_quantity', v_balance.quantity, 'new_quantity', p_new_quantity,
      'delta', v_delta, 'reason', p_reason, 'lot_id', v_lot_id
    )
  );

  RETURN jsonb_build_object(
    'movement_id', v_movement_id,
    'quantity', p_new_quantity,
    'total_value_cents', v_new_value,
    'average_unit_cost_cents', stock_average_unit_cost_cents(p_new_quantity, v_new_value),
    'lot_id', v_lot_id
  );
END;
$$;

-- ── add_work_order_material: +p_lot_code (3a mudanca de aridade, ver README) ─

DROP FUNCTION IF EXISTS add_work_order_material(uuid, text, numeric, integer, integer, uuid, uuid);

CREATE OR REPLACE FUNCTION add_work_order_material(
  p_work_order_id    uuid,
  p_description      text,
  p_quantity         numeric,
  p_unit_cost_cents  integer,
  p_unit_price_cents integer,
  p_product_id       uuid DEFAULT NULL,
  p_warehouse_id     uuid DEFAULT NULL,
  p_lot_code         text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id    uuid;
  v_work_order   work_orders;
  v_product      products;
  v_warehouse_id uuid;
  v_material_id  uuid;
  v_movement_id  uuid;
  v_exit_result  jsonb;
  v_description  text;
  v_unit_cost    integer;
  v_total_cost   integer;
  v_total_price  integer;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL OR NOT has_permission('work_orders.execute') THEN
    RAISE EXCEPTION 'Permissao insuficiente para adicionar material.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_work_order
  FROM work_orders
  WHERE id = p_work_order_id AND tenant_id = v_tenant_id;

  IF v_work_order.id IS NULL THEN
    RAISE EXCEPTION 'OS nao encontrada.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_work_order.status IN ('done','cancelled') THEN
    RAISE EXCEPTION 'OS finalizada nao aceita material.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF p_quantity <= 0 OR p_unit_cost_cents < 0 OR p_unit_price_cents < 0 THEN
    RAISE EXCEPTION 'Material invalido.'
      USING ERRCODE = 'check_violation';
  END IF;

  v_description := LEFT(TRIM(COALESCE(p_description, '')), 300);
  v_unit_cost   := p_unit_cost_cents;

  IF p_product_id IS NOT NULL THEN
    SELECT * INTO v_product
    FROM products
    WHERE id = p_product_id AND tenant_id = v_tenant_id;

    IF v_product.id IS NULL THEN
      RAISE EXCEPTION 'Produto nao encontrado.'
        USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF NOT v_product.track_stock THEN
      v_description := COALESCE(NULLIF(v_description, ''), v_product.name);
    ELSE
      IF p_warehouse_id IS NOT NULL THEN
        SELECT id INTO v_warehouse_id
        FROM warehouses
        WHERE id = p_warehouse_id AND tenant_id = v_tenant_id AND is_active;

        IF v_warehouse_id IS NULL THEN
          RAISE EXCEPTION 'Deposito informado nao encontrado ou inativo.'
            USING ERRCODE = 'insufficient_privilege';
        END IF;
      ELSE
        SELECT id INTO v_warehouse_id
        FROM warehouses
        WHERE tenant_id = v_tenant_id AND is_default AND is_active;

        IF v_warehouse_id IS NULL THEN
          RAISE EXCEPTION
            'Nenhum deposito padrao configurado. Defina um deposito padrao ou '
            'escolha o deposito ao lancar o material.'
            USING ERRCODE = 'check_violation';
        END IF;
      END IF;

      v_exit_result := record_stock_exit(
        p_product_id       => p_product_id,
        p_warehouse_id     => v_warehouse_id,
        p_quantity         => p_quantity,
        p_reason           => 'Consumo na OS #' || v_work_order.number::text,
        p_related_entity   => 'work_orders',
        p_related_entity_id => p_work_order_id,
        p_lot_code         => p_lot_code
      );

      v_movement_id := (v_exit_result->>'movement_id')::uuid;

      SELECT unit_cost_cents INTO v_unit_cost
      FROM stock_movements WHERE id = v_movement_id;

      v_description := COALESCE(NULLIF(v_description, ''), v_product.name);
    END IF;
  END IF;

  IF v_description = '' THEN
    RAISE EXCEPTION 'Descricao do material e obrigatoria.'
      USING ERRCODE = 'check_violation';
  END IF;

  v_total_cost  := ROUND(p_quantity * v_unit_cost);
  v_total_price := ROUND(p_quantity * p_unit_price_cents);

  INSERT INTO work_order_materials (
    tenant_id, work_order_id, description, quantity, unit_cost_cents,
    unit_price_cents, total_cost_cents, total_price_cents, created_by,
    product_id, warehouse_id, stock_movement_id
  ) VALUES (
    v_tenant_id, p_work_order_id, v_description, p_quantity, v_unit_cost,
    p_unit_price_cents, v_total_cost, v_total_price, auth.uid(),
    p_product_id, v_warehouse_id, v_movement_id
  )
  RETURNING id INTO v_material_id;

  UPDATE work_orders
  SET total_cents = total_cents + v_total_price
  WHERE id = p_work_order_id;

  INSERT INTO work_order_events (
    tenant_id, work_order_id, event_type, notes, created_by
  ) VALUES (
    v_tenant_id, p_work_order_id, 'note',
    CASE
      WHEN v_movement_id IS NOT NULL
        THEN 'Material baixado do estoque: ' || LEFT(v_description, 120)
      ELSE 'Material adicionado: ' || LEFT(v_description, 120)
    END,
    auth.uid()
  );

  PERFORM log_audit(
    v_tenant_id,
    'work_order.material.created',
    'work_order_materials',
    v_material_id::text,
    NULL,
    NULL,
    jsonb_build_object(
      'work_order_id', p_work_order_id,
      'total_price_cents', v_total_price,
      'product_id', p_product_id,
      'warehouse_id', v_warehouse_id,
      'stock_movement_id', v_movement_id,
      'from_stock', v_movement_id IS NOT NULL
    )
  );

  RETURN jsonb_build_object(
    'id', v_material_id,
    'total_price_cents', v_total_price,
    'unit_cost_cents', v_unit_cost,
    'stock_movement_id', v_movement_id,
    'from_stock', v_movement_id IS NOT NULL
  );
END;
$$;

-- ── RPCs de leitura: lotes de um produto e histórico de um lote ─────────────

CREATE OR REPLACE FUNCTION list_stock_lots(p_product_id uuid)
RETURNS TABLE (id uuid, code text, created_at timestamptz)
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
  SELECT l.id, l.code, l.created_at
  FROM stock_lots l
  WHERE l.tenant_id = v_tenant_id AND l.product_id = p_product_id
  ORDER BY l.code;
END;
$$;

CREATE OR REPLACE FUNCTION get_lot_history(p_lot_id uuid)
RETURNS TABLE (
  movement_id  uuid,
  kind         text,
  quantity     numeric,
  warehouse_id uuid,
  reason       text,
  related_entity text,
  related_entity_id uuid,
  created_at   timestamptz
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
  SELECT m.id, m.kind, m.quantity, m.warehouse_id, m.reason,
         m.related_entity, m.related_entity_id, m.created_at
  FROM stock_movements m
  JOIN stock_lots l ON l.id = m.lot_id
  WHERE l.id = p_lot_id AND l.tenant_id = v_tenant_id
  ORDER BY m.created_at;
END;
$$;

COMMENT ON COLUMN products.tracking_type IS
  'ADR-024: none (padrao) | lot | serial. serial limita cada movimento a quantidade=1 e so permite uma posse por vez.';
COMMENT ON TABLE stock_lots IS
  'Identidade de lote/numero de serie por produto. Camada de rastreabilidade sobre stock_movements, nao uma segunda contabilidade de custo (ver ADR-020/ADR-024).';

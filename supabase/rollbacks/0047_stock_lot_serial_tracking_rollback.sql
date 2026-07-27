-- Rollback: 0047_stock_lot_serial_tracking
--
-- PERDA DE DADOS: apaga todos os lotes/números de série registrados
-- (stock_lots) e o vínculo lot_id dos movimentos. Os movimentos em si
-- (stock_movements) permanecem — o razão continua correto, só perde a
-- granularidade de rastreio por lote.
--
-- Restaura as versões anteriores de record_stock_entry, record_stock_exit,
-- record_stock_adjustment (de 0042) e add_work_order_material (de 0046).

DROP FUNCTION IF EXISTS get_lot_history(uuid);
DROP FUNCTION IF EXISTS list_stock_lots(uuid);

-- Aridade nova antes da antiga, sempre — senão as duas coexistem.
DROP FUNCTION IF EXISTS add_work_order_material(uuid, text, numeric, integer, integer, uuid, uuid, text);
DROP FUNCTION IF EXISTS record_stock_adjustment(uuid, uuid, numeric, text, text);
DROP FUNCTION IF EXISTS record_stock_exit(uuid, uuid, numeric, text, text, uuid, text);
DROP FUNCTION IF EXISTS record_stock_entry(uuid, uuid, numeric, integer, text, text, uuid, text);
DROP FUNCTION IF EXISTS _sf_resolve_stock_lot(uuid, uuid, numeric, text, boolean);

-- ══════════════════════════════════════════════════════════════════════════
-- Restaura de 0042_stock_ledger.sql
-- ══════════════════════════════════════════════════════════════════════════

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

-- ══════════════════════════════════════════════════════════════════════════
-- Restaura de 0046_fix_material_audit_metadata.sql
-- ══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION add_work_order_material(
  p_work_order_id    uuid,
  p_description      text,
  p_quantity         numeric,
  p_unit_cost_cents  integer,
  p_unit_price_cents integer,
  p_product_id       uuid DEFAULT NULL,
  p_warehouse_id     uuid DEFAULT NULL
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
        p_related_entity_id => p_work_order_id
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

-- ══════════════════════════════════════════════════════════════════════════
-- Remove os objetos criados por 0047
-- ══════════════════════════════════════════════════════════════════════════

ALTER TABLE stock_movements DROP COLUMN IF EXISTS lot_id;

DROP POLICY IF EXISTS "stock_lots_select" ON stock_lots;
DROP TABLE IF EXISTS stock_lots;

ALTER TABLE products DROP COLUMN IF EXISTS tracking_type;

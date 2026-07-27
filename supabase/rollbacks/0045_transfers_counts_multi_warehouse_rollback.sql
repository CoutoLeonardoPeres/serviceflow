-- Rollback: 0045_transfers_counts_multi_warehouse
--
-- ATENCAO — ordem de rollback:
--   Rode este script ANTES de 0043 e 0042. As tabelas removidas aqui
--   referenciam products, warehouses e stock_movements, e a funcao restaurada
--   ao final e a versao de 0043.
--
-- PERDA DE DADOS: apaga o historico de transferencias e de inventarios. Os
-- movimentos de estoque gerados por elas PERMANECEM em stock_movements — o
-- razao e append-only e os saldos continuam corretos. O que se perde e o
-- agrupamento: quais movimentos pertenciam a qual transferencia ou inventario.
--
-- Restaura a versao de 6 parametros de add_work_order_material (0043), que usa
-- sempre o deposito padrao do tenant.

DROP FUNCTION IF EXISTS list_stock_count_items(uuid);
DROP FUNCTION IF EXISTS cancel_stock_count(uuid, text);
DROP FUNCTION IF EXISTS apply_stock_count(uuid);
DROP FUNCTION IF EXISTS set_stock_count_quantity(uuid, numeric);
DROP FUNCTION IF EXISTS create_stock_count(uuid, uuid[], text);
DROP FUNCTION IF EXISTS transfer_stock(uuid, uuid, jsonb, text);

DROP POLICY IF EXISTS "stock_count_items_select"    ON stock_count_items;
DROP POLICY IF EXISTS "stock_counts_select"         ON stock_counts;
DROP POLICY IF EXISTS "stock_transfer_items_select" ON stock_transfer_items;
DROP POLICY IF EXISTS "stock_transfers_select"      ON stock_transfers;

DROP TABLE IF EXISTS stock_count_items;
DROP TABLE IF EXISTS stock_counts;
DROP TABLE IF EXISTS stock_transfer_items;
DROP TABLE IF EXISTS stock_transfers;

DELETE FROM tenant_sequences WHERE kind IN ('stock_transfer','stock_count');

-- A versao de 7 parametros precisa sair antes de recriar a de 6, senao as duas
-- coexistem e chamadas com 6 argumentos ficam ambiguas.
DROP FUNCTION IF EXISTS add_work_order_material(uuid, text, numeric, integer, integer, uuid, uuid);

-- ══════════════════════════════════════════════════════════════════════════
-- Restaura de 0043_work_order_stock_consumption.sql: add_work_order_material
-- ══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION add_work_order_material(
  p_work_order_id   uuid,
  p_description     text,
  p_quantity        numeric,
  p_unit_cost_cents integer,
  p_unit_price_cents integer,
  p_product_id      uuid DEFAULT NULL
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

  -- ── Caminho A: produto do catalogo — baixa o estoque ──────────────────────
  IF p_product_id IS NOT NULL THEN
    SELECT * INTO v_product
    FROM products
    WHERE id = p_product_id AND tenant_id = v_tenant_id;

    IF v_product.id IS NULL THEN
      RAISE EXCEPTION 'Produto nao encontrado.'
        USING ERRCODE = 'insufficient_privilege';
    END IF;

    IF NOT v_product.track_stock THEN
      -- Produto de catalogo sem controle de saldo: registra o vinculo para
      -- rastreabilidade, mas nao movimenta. Nao e erro.
      v_description := COALESCE(NULLIF(v_description, ''), v_product.name);
    ELSE
      SELECT id INTO v_warehouse_id
      FROM warehouses
      WHERE tenant_id = v_tenant_id AND is_default AND is_active;

      IF v_warehouse_id IS NULL THEN
        RAISE EXCEPTION
          'Nenhum deposito padrao configurado. Defina um deposito padrao para '
          'baixar material do estoque.'
          USING ERRCODE = 'check_violation';
      END IF;

      -- record_stock_exit valida saldo, trava a linha e recusa saldo negativo.
      -- Se o saldo nao cobrir, a excecao sobe daqui e nada e gravado — a
      -- transacao inteira volta atras, sem material orfao.
      v_exit_result := record_stock_exit(
        p_product_id       => p_product_id,
        p_warehouse_id     => v_warehouse_id,
        p_quantity         => p_quantity,
        p_reason           => 'Consumo na OS #' || v_work_order.number::text,
        p_related_entity   => 'work_orders',
        p_related_entity_id => p_work_order_id
      );

      v_movement_id := (v_exit_result->>'movement_id')::uuid;

      -- O custo do material e o que ele custou para a empresa, nao o que o
      -- tecnico digitou: usa o custo medio vigente registrado no movimento.
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
    jsonb_build_object(
      'work_order_id', p_work_order_id,
      'total_price_cents', v_total_price,
      'product_id', p_product_id,
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

-- Rollback: 0043_work_order_stock_consumption
--
-- ATENCAO — ordem de rollback:
--   Rode este script ANTES de 0042_stock_ledger_rollback.sql. As colunas
--   removidas aqui referenciam products, warehouses e stock_movements; se 0042
--   cair primeiro, os FKs quebram.
--
-- PERDA DE DADOS: remove o vinculo entre material da OS e produto/movimento.
-- Os movimentos de estoque ja gerados PERMANECEM em stock_movements — a baixa
-- aconteceu de fato e o razao e append-only. Depois deste rollback, esses
-- movimentos ficam sem apontador de volta para a OS no lado do material,
-- restando apenas related_entity/related_entity_id no proprio movimento.
--
-- Restaura a versao de 5 parametros de add_work_order_material (0009), que
-- registra material sem tocar no estoque.

DROP FUNCTION IF EXISTS list_work_order_materials(uuid);

-- A versao de 6 parametros precisa sair antes de recriar a de 5, senao as duas
-- coexistem e chamadas com 5 argumentos ficam ambiguas.
DROP FUNCTION IF EXISTS add_work_order_material(uuid, text, numeric, integer, integer, uuid);

DROP INDEX IF EXISTS idx_work_order_materials_movement;
DROP INDEX IF EXISTS idx_work_order_materials_product;

ALTER TABLE work_order_materials
  DROP COLUMN IF EXISTS stock_movement_id,
  DROP COLUMN IF EXISTS warehouse_id,
  DROP COLUMN IF EXISTS product_id;

-- ══════════════════════════════════════════════════════════════════════════
-- Restaura de 0009_work_order_execution.sql: add_work_order_material
-- ══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION add_work_order_material(
  p_work_order_id uuid,
  p_description text,
  p_quantity numeric,
  p_unit_cost_cents integer,
  p_unit_price_cents integer
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_work_order work_orders;
  v_material_id uuid;
  v_total_cost integer;
  v_total_price integer;
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

  v_total_cost := ROUND(p_quantity * p_unit_cost_cents);
  v_total_price := ROUND(p_quantity * p_unit_price_cents);

  INSERT INTO work_order_materials (
    tenant_id, work_order_id, description, quantity, unit_cost_cents,
    unit_price_cents, total_cost_cents, total_price_cents, created_by
  ) VALUES (
    v_tenant_id, p_work_order_id, LEFT(TRIM(p_description), 300), p_quantity,
    p_unit_cost_cents, p_unit_price_cents, v_total_cost, v_total_price, auth.uid()
  )
  RETURNING id INTO v_material_id;

  UPDATE work_orders
  SET total_cents = total_cents + v_total_price
  WHERE id = p_work_order_id;

  INSERT INTO work_order_events (
    tenant_id, work_order_id, event_type, notes, created_by
  ) VALUES (
    v_tenant_id, p_work_order_id, 'note',
    'Material adicionado: ' || LEFT(TRIM(p_description), 120), auth.uid()
  );

  PERFORM log_audit(
    v_tenant_id,
    'work_order.material.created',
    'work_order_materials',
    v_material_id::text,
    NULL,
    jsonb_build_object('work_order_id', p_work_order_id, 'total_price_cents', v_total_price)
  );

  RETURN jsonb_build_object('id', v_material_id, 'total_price_cents', v_total_price);
END;
$$;

-- =============================================================================
-- Migration: 0043_work_order_stock_consumption
-- Descricao: Consumo de material da OS gerando movimento de estoque — F3-P2
-- Depende de: 0009_work_order_execution, 0042_stock_ledger
-- Rollback: supabase/rollbacks/0043_work_order_stock_consumption_rollback.sql
--
-- Fecha o ADR-016: "na F3, consumo passa a gerar stock_movements".
--
-- DECISAO DE PRODUTO (F3-P2):
--   Material fora do catalogo continua valido. O tecnico pode:
--     a) escolher um produto do catalogo  -> baixa o estoque, custo vem do medio;
--     b) digitar texto livre              -> so registra custo, sem baixa.
--   Travar o campo quando o cadastro esta incompleto ou o saldo divergente
--   punindo quem esta na rua foi considerado pior que aceitar um lancamento
--   sem rastreio. work_order_materials.product_id nulo identifica o caso (b).
--
--   O deposito e sempre o padrao do tenant. Quem tem um deposito so nao ve
--   diferenca; multi-deposito na OS fica para F3-P4.
--
-- MIGRACAO DE DADOS (expand-and-contract):
--   As colunas entram como NULL. Lancamentos historicos ficam com product_id
--   nulo — e correto: eram texto livre e nunca baixaram estoque. Nao ha
--   tentativa de casar descricao com catalogo por similaridade; adivinhar
--   vinculo contabil a partir de texto livre produziria estoque errado com
--   aparencia de certo.
-- =============================================================================

-- ── Expand: colunas de vinculo ───────────────────────────────────────────────

ALTER TABLE work_order_materials
  ADD COLUMN IF NOT EXISTS product_id        uuid REFERENCES products(id),
  ADD COLUMN IF NOT EXISTS warehouse_id      uuid REFERENCES warehouses(id),
  ADD COLUMN IF NOT EXISTS stock_movement_id uuid REFERENCES stock_movements(id);

CREATE INDEX IF NOT EXISTS idx_work_order_materials_product
  ON work_order_materials (product_id)
  WHERE product_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_work_order_materials_movement
  ON work_order_materials (stock_movement_id)
  WHERE stock_movement_id IS NOT NULL;

COMMENT ON COLUMN work_order_materials.product_id IS
  'Produto do catalogo. NULL = lancamento em texto livre, sem baixa de estoque.';
COMMENT ON COLUMN work_order_materials.stock_movement_id IS
  'Movimento gerado pela baixa. NULL quando o lancamento nao passou pelo estoque.';

-- ── Substitui add_work_order_material ────────────────────────────────────────
--
-- ATENCAO: e obrigatorio remover a versao de 5 parametros antes de criar a de
-- 6. `CREATE OR REPLACE` com aridade diferente NAO substitui — cria uma
-- sobrecarga. As duas conviveriam e toda chamada com 5 argumentos passaria a
-- ser ambigua, quebrando o app em runtime com "function is not unique".

DROP FUNCTION IF EXISTS add_work_order_material(uuid, text, numeric, integer, integer);

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

COMMENT ON FUNCTION add_work_order_material IS
  'Adiciona material a OS. Com p_product_id, baixa o estoque e usa o custo medio; sem ele, registra texto livre sem baixa (ADR-016 / F3-P2).';

-- ── Consulta: materiais da OS com origem ─────────────────────────────────────

CREATE OR REPLACE FUNCTION list_work_order_materials(p_work_order_id uuid)
RETURNS TABLE (
  id                uuid,
  description       text,
  quantity          numeric,
  unit_cost_cents   integer,
  unit_price_cents  integer,
  total_cost_cents  integer,
  total_price_cents integer,
  product_id        uuid,
  product_name      text,
  from_stock        boolean,
  created_at        timestamptz
)
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL OR NOT has_permission('work_orders.read') THEN
    RAISE EXCEPTION 'Permissao work_orders.read necessaria.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  RETURN QUERY
  SELECT
    m.id, m.description, m.quantity, m.unit_cost_cents, m.unit_price_cents,
    m.total_cost_cents, m.total_price_cents,
    m.product_id, p.name,
    m.stock_movement_id IS NOT NULL,
    m.created_at
  FROM work_order_materials m
  LEFT JOIN products p ON p.id = m.product_id
  WHERE m.work_order_id = p_work_order_id
    AND m.tenant_id = v_tenant_id
  ORDER BY m.created_at DESC;
END;
$$;

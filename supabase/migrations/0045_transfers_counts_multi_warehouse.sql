-- =============================================================================
-- Migration: 0045_transfers_counts_multi_warehouse
-- Descricao: Transferencias entre depositos, inventario ciclico e escolha de
--            deposito no consumo da OS — F3-P4
-- Depende de: 0042_stock_ledger, 0043_work_order_stock_consumption
-- Rollback: supabase/rollbacks/0045_transfers_counts_multi_warehouse_rollback.sql
--
-- CONSERVACAO DE VALOR NA TRANSFERENCIA (o ponto critico desta migration):
--   Transferir nao cria nem destroi valor: o que sai da origem entra no destino,
--   ate o ultimo centavo. Por isso a transferencia NAO usa record_stock_exit +
--   record_stock_entry. Aqueles RPCs recalculam custo a partir de unit_cost, e
--   round(qtd * round(V/qtd)) != V no caso geral — cada transferencia perderia
--   ou criaria centavos, e o valor total do estoque derivaria com o tempo.
--   Aqui o valor V e calculado uma vez na origem e gravado identico no destino.
--
-- ORDEM DE TRAVA:
--   Transferencias simultaneas A->B e B->A poderiam travar uma a outra. As
--   linhas de saldo sao travadas sempre na ordem crescente de warehouse_id,
--   o que garante ordem global consistente e elimina o deadlock.
-- =============================================================================

-- ── Transferencias ───────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS stock_transfers (
  id                uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id         uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  number            bigint      NOT NULL,
  from_warehouse_id uuid        NOT NULL REFERENCES warehouses(id),
  to_warehouse_id   uuid        NOT NULL REFERENCES warehouses(id),
  reason            text        CHECK (reason IS NULL OR char_length(reason) <= 500),
  total_value_cents bigint      NOT NULL DEFAULT 0 CHECK (total_value_cents >= 0),
  created_at        timestamptz NOT NULL DEFAULT now(),
  created_by        uuid        REFERENCES auth.users(id),
  CONSTRAINT uq_stock_transfers_tenant_number UNIQUE (tenant_id, number),
  CONSTRAINT ck_stock_transfers_distinct_warehouses
    CHECK (from_warehouse_id <> to_warehouse_id)
);

CREATE INDEX IF NOT EXISTS idx_stock_transfers_tenant
  ON stock_transfers (tenant_id, created_at DESC);

CREATE TABLE IF NOT EXISTS stock_transfer_items (
  id           uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid          NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  transfer_id  uuid          NOT NULL REFERENCES stock_transfers(id) ON DELETE CASCADE,
  product_id   uuid          NOT NULL REFERENCES products(id),
  quantity     numeric(12,3) NOT NULL CHECK (quantity > 0),
  value_cents  bigint        NOT NULL CHECK (value_cents >= 0),
  out_movement_id uuid       REFERENCES stock_movements(id),
  in_movement_id  uuid       REFERENCES stock_movements(id),
  created_at   timestamptz   NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_stock_transfer_items_transfer
  ON stock_transfer_items (transfer_id);

-- ── Inventario ciclico ───────────────────────────────────────────────────────
-- Sessao persistida em vez de ajuste em lote direto: a contagem real costuma
-- se estender no tempo, e o registro de quem contou o que, e quando, e a
-- justificativa auditavel do ajuste que vem depois.

CREATE TABLE IF NOT EXISTS stock_counts (
  id           uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id    uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  number       bigint      NOT NULL,
  warehouse_id uuid        NOT NULL REFERENCES warehouses(id),
  status       text        NOT NULL DEFAULT 'open'
                           CHECK (status IN ('open','applied','cancelled')),
  notes        text        CHECK (notes IS NULL OR char_length(notes) <= 1000),
  applied_at   timestamptz,
  cancelled_at timestamptz,
  created_at   timestamptz NOT NULL DEFAULT now(),
  created_by   uuid        REFERENCES auth.users(id),
  applied_by   uuid        REFERENCES auth.users(id),
  CONSTRAINT uq_stock_counts_tenant_number UNIQUE (tenant_id, number)
);

CREATE INDEX IF NOT EXISTS idx_stock_counts_tenant
  ON stock_counts (tenant_id, status, created_at DESC);

CREATE TABLE IF NOT EXISTS stock_count_items (
  id                uuid          PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id         uuid          NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  count_id          uuid          NOT NULL REFERENCES stock_counts(id) ON DELETE CASCADE,
  product_id        uuid          NOT NULL REFERENCES products(id),
  -- Saldo do sistema no momento em que o item entrou na contagem. Serve de
  -- referencia; o saldo real e relido na aplicacao, porque pode ter mudado.
  system_quantity   numeric(12,3) NOT NULL,
  counted_quantity  numeric(12,3) CHECK (counted_quantity IS NULL OR counted_quantity >= 0),
  created_at        timestamptz   NOT NULL DEFAULT now(),
  CONSTRAINT uq_stock_count_items_count_product UNIQUE (count_id, product_id)
);

CREATE INDEX IF NOT EXISTS idx_stock_count_items_count
  ON stock_count_items (count_id);

-- ── RLS ──────────────────────────────────────────────────────────────────────

ALTER TABLE stock_transfers      ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_transfer_items ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_counts         ENABLE ROW LEVEL SECURITY;
ALTER TABLE stock_count_items    ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "stock_transfers_select" ON stock_transfers;
CREATE POLICY "stock_transfers_select" ON stock_transfers
  FOR SELECT USING (tenant_id = current_tenant_id() AND has_permission('stock.read'));

DROP POLICY IF EXISTS "stock_transfer_items_select" ON stock_transfer_items;
CREATE POLICY "stock_transfer_items_select" ON stock_transfer_items
  FOR SELECT USING (tenant_id = current_tenant_id() AND has_permission('stock.read'));

DROP POLICY IF EXISTS "stock_counts_select" ON stock_counts;
CREATE POLICY "stock_counts_select" ON stock_counts
  FOR SELECT USING (tenant_id = current_tenant_id() AND has_permission('stock.read'));

DROP POLICY IF EXISTS "stock_count_items_select" ON stock_count_items;
CREATE POLICY "stock_count_items_select" ON stock_count_items
  FOR SELECT USING (tenant_id = current_tenant_id() AND has_permission('stock.read'));

-- ── RPC: transferir entre depositos ──────────────────────────────────────────

CREATE OR REPLACE FUNCTION transfer_stock(
  p_from_warehouse_id uuid,
  p_to_warehouse_id   uuid,
  p_items             jsonb,
  p_reason            text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id   uuid;
  v_transfer_id uuid;
  v_number      bigint;
  v_item        jsonb;
  v_product_id  uuid;
  v_qty         numeric;
  v_from_bal    stock_balances;
  v_to_bal      stock_balances;
  v_value_out   bigint;
  v_unit_cost   integer;
  v_out_mov     uuid;
  v_in_mov      uuid;
  v_total       bigint := 0;
  v_ok          boolean;
  v_lock_first  uuid;
  v_lock_second uuid;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL OR NOT has_permission('stock.write') THEN
    RAISE EXCEPTION 'Permissao stock.write necessaria.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_from_warehouse_id = p_to_warehouse_id THEN
    RAISE EXCEPTION 'Origem e destino devem ser depositos diferentes.'
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT COUNT(*) = 2 INTO v_ok
  FROM warehouses
  WHERE id IN (p_from_warehouse_id, p_to_warehouse_id)
    AND tenant_id = v_tenant_id AND is_active;
  IF NOT v_ok THEN
    RAISE EXCEPTION 'Deposito de origem ou destino nao encontrado ou inativo.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_items IS NULL OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Informe ao menos um item para transferir.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- Ordem de trava determinstica: sempre o menor warehouse_id primeiro.
  IF p_from_warehouse_id < p_to_warehouse_id THEN
    v_lock_first  := p_from_warehouse_id;
    v_lock_second := p_to_warehouse_id;
  ELSE
    v_lock_first  := p_to_warehouse_id;
    v_lock_second := p_from_warehouse_id;
  END IF;

  v_number := next_sequence(v_tenant_id, 'stock_transfer');

  INSERT INTO stock_transfers (
    tenant_id, number, from_warehouse_id, to_warehouse_id, reason, created_by
  ) VALUES (
    v_tenant_id, v_number, p_from_warehouse_id, p_to_warehouse_id,
    NULLIF(TRIM(COALESCE(p_reason, '')), ''), auth.uid()
  ) RETURNING id INTO v_transfer_id;

  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items) LOOP
    v_product_id := (v_item->>'product_id')::uuid;
    v_qty        := (v_item->>'quantity')::numeric;

    IF v_qty IS NULL OR v_qty <= 0 THEN
      RAISE EXCEPTION 'Quantidade invalida na transferencia.'
        USING ERRCODE = 'check_violation';
    END IF;

    PERFORM _sf_validate_stock_target(v_tenant_id, p_from_warehouse_id, v_product_id);
    PERFORM _sf_validate_stock_target(v_tenant_id, p_to_warehouse_id, v_product_id);

    -- Trava nas duas pontas, na ordem fixa, antes de ler qualquer saldo.
    PERFORM _sf_lock_stock_balance(v_tenant_id, v_lock_first, v_product_id);
    PERFORM _sf_lock_stock_balance(v_tenant_id, v_lock_second, v_product_id);

    SELECT * INTO v_from_bal FROM stock_balances
    WHERE warehouse_id = p_from_warehouse_id AND product_id = v_product_id;

    SELECT * INTO v_to_bal FROM stock_balances
    WHERE warehouse_id = p_to_warehouse_id AND product_id = v_product_id;

    IF v_from_bal.quantity < v_qty THEN
      RAISE EXCEPTION
        'Saldo insuficiente na origem: disponivel %, solicitado %.',
        v_from_bal.quantity, v_qty
        USING ERRCODE = 'check_violation';
    END IF;

    -- Valor que viaja com a mercadoria. Calculado UMA vez; o destino recebe
    -- exatamente este numero, sem recalcular a partir de custo unitario.
    IF v_from_bal.quantity = v_qty THEN
      v_value_out := v_from_bal.total_value_cents;
    ELSE
      v_value_out := round(
        v_from_bal.total_value_cents::numeric * v_qty / v_from_bal.quantity
      )::bigint;
    END IF;

    v_unit_cost := stock_average_unit_cost_cents(
      v_from_bal.quantity, v_from_bal.total_value_cents
    );

    -- Origem
    UPDATE stock_balances
    SET quantity = v_from_bal.quantity - v_qty,
        total_value_cents = v_from_bal.total_value_cents - v_value_out,
        updated_at = now()
    WHERE id = v_from_bal.id;

    INSERT INTO stock_movements (
      tenant_id, warehouse_id, product_id, kind, quantity,
      unit_cost_cents, total_cost_cents, quantity_after, value_after_cents,
      reason, related_entity, related_entity_id, created_by
    ) VALUES (
      v_tenant_id, p_from_warehouse_id, v_product_id, 'out', v_qty,
      v_unit_cost, v_value_out,
      v_from_bal.quantity - v_qty, v_from_bal.total_value_cents - v_value_out,
      'Transferencia #' || v_number::text || ' (saida)',
      'stock_transfers', v_transfer_id, auth.uid()
    ) RETURNING id INTO v_out_mov;

    -- Destino recebe o MESMO valor que saiu.
    UPDATE stock_balances
    SET quantity = v_to_bal.quantity + v_qty,
        total_value_cents = v_to_bal.total_value_cents + v_value_out,
        updated_at = now()
    WHERE id = v_to_bal.id;

    INSERT INTO stock_movements (
      tenant_id, warehouse_id, product_id, kind, quantity,
      unit_cost_cents, total_cost_cents, quantity_after, value_after_cents,
      reason, related_entity, related_entity_id, created_by
    ) VALUES (
      v_tenant_id, p_to_warehouse_id, v_product_id, 'in', v_qty,
      v_unit_cost, v_value_out,
      v_to_bal.quantity + v_qty, v_to_bal.total_value_cents + v_value_out,
      'Transferencia #' || v_number::text || ' (entrada)',
      'stock_transfers', v_transfer_id, auth.uid()
    ) RETURNING id INTO v_in_mov;

    INSERT INTO stock_transfer_items (
      tenant_id, transfer_id, product_id, quantity, value_cents,
      out_movement_id, in_movement_id
    ) VALUES (
      v_tenant_id, v_transfer_id, v_product_id, v_qty, v_value_out,
      v_out_mov, v_in_mov
    );

    v_total := v_total + v_value_out;
  END LOOP;

  UPDATE stock_transfers SET total_value_cents = v_total WHERE id = v_transfer_id;

  PERFORM log_audit(
    v_tenant_id, 'stock.transfer', 'stock_transfers', v_transfer_id::text, NULL,
    jsonb_build_object(
      'number', v_number,
      'from_warehouse_id', p_from_warehouse_id,
      'to_warehouse_id', p_to_warehouse_id,
      'total_value_cents', v_total
    )
  );

  RETURN jsonb_build_object(
    'id', v_transfer_id, 'number', v_number, 'total_value_cents', v_total
  );
END;
$$;

-- ── RPC: abrir contagem ──────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION create_stock_count(
  p_warehouse_id uuid,
  p_product_ids  uuid[] DEFAULT NULL,
  p_notes        text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_count_id  uuid;
  v_number    bigint;
  v_ok        boolean;
  v_items     int;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL OR NOT has_permission('stock.adjust') THEN
    RAISE EXCEPTION 'Permissao stock.adjust necessaria para abrir contagem.'
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

  v_number := next_sequence(v_tenant_id, 'stock_count');

  INSERT INTO stock_counts (tenant_id, number, warehouse_id, notes, created_by)
  VALUES (v_tenant_id, v_number, p_warehouse_id, p_notes, auth.uid())
  RETURNING id INTO v_count_id;

  -- Sem lista, entra tudo que tem saldo no deposito. Com lista, so os
  -- informados — permite contagem ciclica por categoria ou curva ABC.
  INSERT INTO stock_count_items (tenant_id, count_id, product_id, system_quantity)
  SELECT v_tenant_id, v_count_id, b.product_id, b.quantity
  FROM stock_balances b
  JOIN products p ON p.id = b.product_id
  WHERE b.tenant_id = v_tenant_id
    AND b.warehouse_id = p_warehouse_id
    AND p.is_active AND p.track_stock
    AND (p_product_ids IS NULL OR b.product_id = ANY(p_product_ids));

  GET DIAGNOSTICS v_items = ROW_COUNT;

  PERFORM log_audit(
    v_tenant_id, 'stock.count.created', 'stock_counts', v_count_id::text, NULL,
    jsonb_build_object('number', v_number, 'items', v_items)
  );

  RETURN jsonb_build_object(
    'id', v_count_id, 'number', v_number, 'items', v_items
  );
END;
$$;

-- ── RPC: registrar quantidade contada ────────────────────────────────────────

CREATE OR REPLACE FUNCTION set_stock_count_quantity(
  p_count_item_id uuid,
  p_quantity      numeric
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_status    text;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL OR NOT has_permission('stock.adjust') THEN
    RAISE EXCEPTION 'Permissao stock.adjust necessaria.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_quantity IS NOT NULL AND p_quantity < 0 THEN
    RAISE EXCEPTION 'Quantidade contada invalida.'
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT c.status INTO v_status
  FROM stock_count_items i
  JOIN stock_counts c ON c.id = i.count_id
  WHERE i.id = p_count_item_id AND i.tenant_id = v_tenant_id;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Item de contagem nao encontrado.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_status <> 'open' THEN
    RAISE EXCEPTION 'Contagem ja finalizada nao aceita alteracao.'
      USING ERRCODE = 'check_violation';
  END IF;

  UPDATE stock_count_items
  SET counted_quantity = p_quantity
  WHERE id = p_count_item_id;
END;
$$;

-- ── RPC: aplicar contagem ────────────────────────────────────────────────────
-- Gera um ajuste por item divergente. Reutiliza record_stock_adjustment, que
-- ja trava a linha, exige motivo e audita — nao ha caminho paralelo de escrita.

CREATE OR REPLACE FUNCTION apply_stock_count(p_count_id uuid)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_count     stock_counts;
  v_item      record;
  v_current   numeric;
  v_adjusted  int := 0;
  v_skipped   int := 0;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL OR NOT has_permission('stock.adjust') THEN
    RAISE EXCEPTION 'Permissao stock.adjust necessaria.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_count
  FROM stock_counts
  WHERE id = p_count_id AND tenant_id = v_tenant_id
  FOR UPDATE;

  IF v_count.id IS NULL THEN
    RAISE EXCEPTION 'Contagem nao encontrada.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_count.status <> 'open' THEN
    RAISE EXCEPTION 'Contagem com status "%" nao pode ser aplicada.', v_count.status
      USING ERRCODE = 'check_violation';
  END IF;

  FOR v_item IN
    SELECT id, product_id, counted_quantity
    FROM stock_count_items
    WHERE count_id = p_count_id AND counted_quantity IS NOT NULL
  LOOP
    -- Rele o saldo atual: pode ter mudado desde a abertura da contagem, e o
    -- ajuste precisa partir do que existe agora, nao do snapshot.
    SELECT quantity INTO v_current
    FROM stock_balances
    WHERE warehouse_id = v_count.warehouse_id AND product_id = v_item.product_id;

    IF v_current IS NULL OR v_current = v_item.counted_quantity THEN
      v_skipped := v_skipped + 1;
      CONTINUE;
    END IF;

    PERFORM record_stock_adjustment(
      p_product_id   => v_item.product_id,
      p_warehouse_id => v_count.warehouse_id,
      p_new_quantity => v_item.counted_quantity,
      p_reason       => 'Inventario #' || v_count.number::text
    );

    v_adjusted := v_adjusted + 1;
  END LOOP;

  UPDATE stock_counts
  SET status = 'applied', applied_at = now(), applied_by = auth.uid()
  WHERE id = p_count_id;

  PERFORM log_audit(
    v_tenant_id, 'stock.count.applied', 'stock_counts', p_count_id::text, NULL,
    jsonb_build_object(
      'number', v_count.number, 'adjusted', v_adjusted, 'unchanged', v_skipped
    )
  );

  RETURN jsonb_build_object('adjusted', v_adjusted, 'unchanged', v_skipped);
END;
$$;

CREATE OR REPLACE FUNCTION cancel_stock_count(p_count_id uuid, p_reason text)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_status    text;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL OR NOT has_permission('stock.adjust') THEN
    RAISE EXCEPTION 'Permissao stock.adjust necessaria.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT status INTO v_status
  FROM stock_counts WHERE id = p_count_id AND tenant_id = v_tenant_id;

  IF v_status IS NULL THEN
    RAISE EXCEPTION 'Contagem nao encontrada.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_status <> 'open' THEN
    RAISE EXCEPTION 'Somente contagem aberta pode ser cancelada.'
      USING ERRCODE = 'check_violation';
  END IF;

  UPDATE stock_counts
  SET status = 'cancelled', cancelled_at = now()
  WHERE id = p_count_id;

  PERFORM log_audit(
    v_tenant_id, 'stock.count.cancelled', 'stock_counts', p_count_id::text,
    NULL, jsonb_build_object('reason', p_reason)
  );
END;
$$;

CREATE OR REPLACE FUNCTION list_stock_count_items(p_count_id uuid)
RETURNS TABLE (
  id               uuid,
  product_id       uuid,
  product_name     text,
  sku              text,
  unit             text,
  system_quantity  numeric,
  counted_quantity numeric,
  difference       numeric
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
    i.id, i.product_id, p.name, p.sku, p.unit,
    i.system_quantity, i.counted_quantity,
    CASE
      WHEN i.counted_quantity IS NULL THEN NULL
      ELSE i.counted_quantity - i.system_quantity
    END
  FROM stock_count_items i
  JOIN products p ON p.id = i.product_id
  WHERE i.count_id = p_count_id AND i.tenant_id = v_tenant_id
  ORDER BY p.name;
END;
$$;

-- ── Multi-deposito no consumo da OS ──────────────────────────────────────────
--
-- ATENCAO: add_work_order_material vai de 6 para 7 parametros. Pelo mesmo
-- motivo de 0043, e obrigatorio remover a versao anterior antes — CREATE OR
-- REPLACE com aridade diferente cria sobrecarga, e chamadas com 6 argumentos
-- ficariam ambiguas ("function is not unique").

DROP FUNCTION IF EXISTS add_work_order_material(uuid, text, numeric, integer, integer, uuid);

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
      -- Novidade do F3-P4: deposito escolhido; sem escolha, cai no padrao.
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

COMMENT ON FUNCTION transfer_stock IS
  'Transfere entre depositos conservando o valor exato (F3-P4). Trava as duas pontas em ordem crescente de warehouse_id para evitar deadlock.';
COMMENT ON TABLE stock_counts IS
  'Sessao de inventario ciclico. Aplicar gera ajustes via record_stock_adjustment, um por item divergente.';

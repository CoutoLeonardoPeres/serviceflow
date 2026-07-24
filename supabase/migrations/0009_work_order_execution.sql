-- =============================================================================
-- Migration: 0009_work_order_execution
-- Descricao: Horas trabalhadas e materiais de execucao da OS — Entrega 7
-- Depende de: 0008_work_orders
-- Rollback: supabase/rollbacks/0009_work_order_execution_rollback.sql
-- =============================================================================

CREATE TABLE work_order_time_entries (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  work_order_id uuid        NOT NULL REFERENCES work_orders(id) ON DELETE CASCADE,
  technician_id uuid        REFERENCES auth.users(id),
  started_at    timestamptz NOT NULL,
  ended_at      timestamptz NOT NULL,
  duration_minutes integer  NOT NULL CHECK (duration_minutes > 0 AND duration_minutes <= 1440),
  notes         text        CHECK (notes IS NULL OR char_length(notes) <= 1000),
  created_at    timestamptz NOT NULL DEFAULT now(),
  created_by    uuid        REFERENCES auth.users(id),
  CONSTRAINT chk_work_order_time_period CHECK (ended_at > started_at)
);

CREATE INDEX idx_work_order_time_entries_work_order
  ON work_order_time_entries (work_order_id, started_at DESC);
CREATE INDEX idx_work_order_time_entries_technician
  ON work_order_time_entries (tenant_id, technician_id, started_at DESC);

CREATE TABLE work_order_materials (
  id               uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id        uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  work_order_id    uuid        NOT NULL REFERENCES work_orders(id) ON DELETE CASCADE,
  description      text        NOT NULL CHECK (char_length(description) BETWEEN 3 AND 300),
  quantity         numeric(12,3) NOT NULL CHECK (quantity > 0),
  unit_cost_cents  integer     NOT NULL DEFAULT 0 CHECK (unit_cost_cents >= 0),
  unit_price_cents integer     NOT NULL DEFAULT 0 CHECK (unit_price_cents >= 0),
  total_cost_cents integer     NOT NULL DEFAULT 0 CHECK (total_cost_cents >= 0),
  total_price_cents integer    NOT NULL DEFAULT 0 CHECK (total_price_cents >= 0),
  created_at       timestamptz NOT NULL DEFAULT now(),
  created_by       uuid        REFERENCES auth.users(id)
);

CREATE INDEX idx_work_order_materials_work_order
  ON work_order_materials (work_order_id, created_at DESC);

CREATE OR REPLACE FUNCTION record_work_order_time_entry(
  p_work_order_id uuid,
  p_started_at timestamptz,
  p_ended_at timestamptz,
  p_notes text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_work_order work_orders;
  v_minutes integer;
  v_entry_id uuid;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL OR NOT has_permission('work_orders.execute') THEN
    RAISE EXCEPTION 'Permissao insuficiente para registrar horas.'
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
    RAISE EXCEPTION 'OS finalizada nao aceita horas.'
      USING ERRCODE = 'check_violation';
  END IF;

  v_minutes := FLOOR(EXTRACT(EPOCH FROM (p_ended_at - p_started_at)) / 60)::integer;
  IF v_minutes <= 0 OR v_minutes > 1440 THEN
    RAISE EXCEPTION 'Periodo de horas invalido.'
      USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO work_order_time_entries (
    tenant_id, work_order_id, technician_id, started_at, ended_at,
    duration_minutes, notes, created_by
  ) VALUES (
    v_tenant_id, p_work_order_id, auth.uid(), p_started_at, p_ended_at,
    v_minutes, p_notes, auth.uid()
  )
  RETURNING id INTO v_entry_id;

  UPDATE work_orders
  SET status = CASE WHEN status = 'opened' THEN 'in_progress' ELSE status END
  WHERE id = p_work_order_id;

  INSERT INTO work_order_events (
    tenant_id, work_order_id, event_type, notes, created_by
  ) VALUES (
    v_tenant_id, p_work_order_id, 'note',
    'Horas registradas: ' || v_minutes::text || ' min', auth.uid()
  );

  PERFORM log_audit(
    v_tenant_id,
    'work_order.time_entry.created',
    'work_order_time_entries',
    v_entry_id::text,
    NULL,
    jsonb_build_object('work_order_id', p_work_order_id, 'duration_minutes', v_minutes)
  );

  RETURN jsonb_build_object('id', v_entry_id, 'duration_minutes', v_minutes);
END;
$$;

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

ALTER TABLE work_order_time_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE work_order_materials ENABLE ROW LEVEL SECURITY;

CREATE POLICY "work_order_time_entries_select" ON work_order_time_entries
  FOR SELECT
  USING (tenant_id = current_tenant_id() AND has_permission('work_orders.read'));

CREATE POLICY "work_order_time_entries_insert" ON work_order_time_entries
  FOR INSERT
  WITH CHECK (has_permission('work_orders.execute'));

CREATE POLICY "work_order_materials_select" ON work_order_materials
  FOR SELECT
  USING (tenant_id = current_tenant_id() AND has_permission('work_orders.read'));

CREATE POLICY "work_order_materials_insert" ON work_order_materials
  FOR INSERT
  WITH CHECK (has_permission('work_orders.execute'));

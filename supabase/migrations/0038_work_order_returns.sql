-- ============================================================
-- 0038_work_order_returns.sql
-- Retornos: OS vinculada a uma OS concluída (parent_work_order_id)
-- ============================================================

-- ── Campo de vínculo ──────────────────────────────────────────────────────────

ALTER TABLE work_orders
  ADD COLUMN IF NOT EXISTS parent_work_order_id UUID
    REFERENCES work_orders(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_work_orders_parent
  ON work_orders(parent_work_order_id)
  WHERE parent_work_order_id IS NOT NULL;

-- ── Expandir event_type para incluir 'return_created' ────────────────────────
-- Abordagem expand-and-contract: drop constraint antiga, adiciona com novo valor.

ALTER TABLE work_order_events
  DROP CONSTRAINT IF EXISTS work_order_events_event_type_check;

ALTER TABLE work_order_events
  ADD CONSTRAINT work_order_events_event_type_check
    CHECK (event_type IN (
      'created','converted_from_quotation','started',
      'paused','resumed','completed','cancelled','note',
      'return_created'
    ));

-- ── RPC: create_return_work_order ─────────────────────────────────────────────
--
-- Cria uma nova OS de retorno vinculada à OS original.
-- Só é permitido quando a OS original está com status 'done'.
-- O retorno herda: customer_id, request_id, address_id, título prefixado.
-- O evento 'return_created' é registrado na OS original.

CREATE OR REPLACE FUNCTION create_return_work_order(
  p_original_id UUID,
  p_reason      TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id     UUID;
  v_status        TEXT;
  v_customer_id   UUID;
  v_request_id    UUID;
  v_address_id    UUID;
  v_title         TEXT;
  v_description   TEXT;
  v_new_number    BIGINT;
  v_new_id        UUID;
  v_customer_name TEXT;
BEGIN
  SELECT tenant_id, status, customer_id, request_id, address_id, title
    INTO v_tenant_id, v_status, v_customer_id, v_request_id, v_address_id, v_title
    FROM work_orders
   WHERE id = p_original_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'OS não encontrada.'
      USING ERRCODE = 'P0001';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM tenant_members
     WHERE user_id   = auth.uid()
       AND tenant_id = v_tenant_id
       AND is_active = TRUE
  ) THEN
    RAISE EXCEPTION 'Sem permissão para criar retorno desta OS.'
      USING ERRCODE = '42501';
  END IF;

  IF NOT has_permission('work_orders.manage') THEN
    RAISE EXCEPTION 'Permissão insuficiente para criar retorno.'
      USING ERRCODE = '42501';
  END IF;

  IF v_status <> 'done' THEN
    RAISE EXCEPTION 'Retorno só pode ser criado para OS concluída (status atual: %).',
      v_status USING ERRCODE = 'P0001';
  END IF;

  IF trim(COALESCE(p_reason, '')) = '' THEN
    RAISE EXCEPTION 'Informe o motivo do retorno.'
      USING ERRCODE = 'P0001';
  END IF;

  v_description := 'Retorno: ' || trim(p_reason);
  -- Garante que description não exceda o CHECK de 4000 chars
  v_description := LEFT(v_description, 4000);

  -- Título prefixado com [Retorno]
  v_title := LEFT('[Retorno] ' || v_title, 180);

  v_new_number := next_sequence(v_tenant_id, 'work_order');

  INSERT INTO work_orders(
    tenant_id, number, customer_id, request_id, address_id,
    status, title, description, total_cents,
    parent_work_order_id, created_by, updated_by
  ) VALUES (
    v_tenant_id, v_new_number, v_customer_id, v_request_id, v_address_id,
    'opened', v_title, v_description, 0,
    p_original_id, auth.uid(), auth.uid()
  )
  RETURNING id INTO v_new_id;

  -- Evento na OS original
  INSERT INTO work_order_events(tenant_id, work_order_id, event_type, notes, created_by)
  VALUES (
    v_tenant_id, p_original_id, 'return_created',
    'Retorno criado (OS #' || v_new_number || '): ' || trim(p_reason),
    auth.uid()
  );

  -- Evento na OS de retorno
  INSERT INTO work_order_events(tenant_id, work_order_id, event_type, notes, created_by)
  VALUES (
    v_tenant_id, v_new_id, 'created',
    'Retorno da OS ' || p_original_id::text,
    auth.uid()
  );

  SELECT name INTO v_customer_name FROM customers WHERE id = v_customer_id;

  RETURN (
    SELECT to_jsonb(wo)
      || jsonb_build_object('customers', jsonb_build_object('name', v_customer_name))
      || jsonb_build_object('service_requests', NULL)
      || jsonb_build_object('quotations', NULL)
    FROM work_orders wo WHERE wo.id = v_new_id
  );
END;
$$;

COMMENT ON FUNCTION create_return_work_order(UUID, TEXT) IS
  'Cria OS de retorno vinculada à OS original (precisa estar done). Registra evento em ambas.';

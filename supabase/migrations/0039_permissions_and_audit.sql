-- ============================================================
-- 0039_permissions_and_audit.sql
-- F2-P2: Permissões refinadas + log_audit nas ações F2-P1
--
-- Problemas corrigidos:
--   1. cancel_quotation usava tenant_members em vez de has_permission
--   2. cancel_work_order usava tenant_members em vez de has_permission
--   3. cancel_quotation, cancel_work_order, create_new_quotation_version
--      e create_return_work_order não emitiam log_audit
--
-- Novo:
--   4. RPC list_audit_events — trilha auditável pelo Flutter
-- ============================================================

-- ── 1. Corrigir + auditar cancel_quotation ────────────────────────────────────

CREATE OR REPLACE FUNCTION cancel_quotation(
  p_quotation_id UUID,
  p_reason       TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id UUID;
  v_status    TEXT;
BEGIN
  -- Localiza e valida tenant
  SELECT tenant_id, status
    INTO v_tenant_id, v_status
    FROM quotations
   WHERE id = p_quotation_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Orçamento não encontrado.'
      USING ERRCODE = 'P0001';
  END IF;

  -- Verifica pertencimento ao tenant
  IF NOT EXISTS (
    SELECT 1 FROM tenant_memberships
     WHERE user_id   = auth.uid()
       AND tenant_id = v_tenant_id
       AND status    = 'active'
  ) THEN
    RAISE EXCEPTION 'Sem permissão para cancelar este orçamento.'
      USING ERRCODE = '42501';
  END IF;

  -- Verifica permissão refinada
  IF NOT has_permission('quotations.write') THEN
    RAISE EXCEPTION 'Permissão quotations.write necessária para cancelar.'
      USING ERRCODE = '42501';
  END IF;

  -- Valida status
  IF v_status IN ('approved', 'cancelled') THEN
    RAISE EXCEPTION 'Orçamento não pode ser cancelado no status "%".', v_status
      USING ERRCODE = 'P0001';
  END IF;

  -- Valida motivo
  IF trim(COALESCE(p_reason, '')) = '' THEN
    RAISE EXCEPTION 'Informe o motivo do cancelamento.'
      USING ERRCODE = 'P0001';
  END IF;

  -- Atualiza
  UPDATE quotations
     SET status              = 'cancelled',
         cancelled_at        = now(),
         cancellation_reason = trim(p_reason),
         updated_at          = now()
   WHERE id = p_quotation_id;

  -- Histórico de status
  INSERT INTO quotation_status_history(tenant_id, quotation_id, status, notes, changed_by)
  VALUES (v_tenant_id, p_quotation_id, 'cancelled', trim(p_reason), auth.uid());

  -- Auditoria
  PERFORM log_audit(
    v_tenant_id,
    'quotation.cancelled',
    'quotations',
    p_quotation_id::text,
    jsonb_build_object('status', v_status),
    jsonb_build_object('status', 'cancelled', 'cancellation_reason', trim(p_reason))
  );
END;
$$;

COMMENT ON FUNCTION cancel_quotation(UUID, TEXT) IS
  'Cancela um orçamento com motivo obrigatório. Exige quotations.write. Emite log_audit.';

-- ── 2. Corrigir + auditar cancel_work_order ───────────────────────────────────

CREATE OR REPLACE FUNCTION cancel_work_order(
  p_work_order_id UUID,
  p_reason        TEXT
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id UUID;
  v_status    TEXT;
BEGIN
  SELECT tenant_id, status
    INTO v_tenant_id, v_status
    FROM work_orders
   WHERE id = p_work_order_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'OS não encontrada.'
      USING ERRCODE = 'P0001';
  END IF;

  -- Verifica pertencimento ao tenant
  IF NOT EXISTS (
    SELECT 1 FROM tenant_memberships
     WHERE user_id   = auth.uid()
       AND tenant_id = v_tenant_id
       AND status    = 'active'
  ) THEN
    RAISE EXCEPTION 'Sem permissão para cancelar esta OS.'
      USING ERRCODE = '42501';
  END IF;

  -- Verifica permissão refinada
  IF NOT has_permission('work_orders.manage') THEN
    RAISE EXCEPTION 'Permissão work_orders.manage necessária para cancelar.'
      USING ERRCODE = '42501';
  END IF;

  IF v_status IN ('done', 'cancelled') THEN
    RAISE EXCEPTION 'OS não pode ser cancelada no status "%".', v_status
      USING ERRCODE = 'P0001';
  END IF;

  IF trim(COALESCE(p_reason, '')) = '' THEN
    RAISE EXCEPTION 'Informe o motivo do cancelamento.'
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE work_orders
     SET status              = 'cancelled',
         cancelled_at        = now(),
         cancellation_reason = trim(p_reason),
         updated_at          = now()
   WHERE id = p_work_order_id;

  INSERT INTO work_order_events(tenant_id, work_order_id, event_type, notes, created_by)
  VALUES (v_tenant_id, p_work_order_id, 'cancelled', trim(p_reason), auth.uid());

  -- Auditoria
  PERFORM log_audit(
    v_tenant_id,
    'work_order.cancelled',
    'work_orders',
    p_work_order_id::text,
    jsonb_build_object('status', v_status),
    jsonb_build_object('status', 'cancelled', 'cancellation_reason', trim(p_reason))
  );
END;
$$;

COMMENT ON FUNCTION cancel_work_order(UUID, TEXT) IS
  'Cancela uma OS com motivo obrigatório. Exige work_orders.manage. Emite log_audit.';

-- ── 3. Auditar create_new_quotation_version ───────────────────────────────────
-- Inclui log_audit preservando toda a lógica original de 0037.

CREATE OR REPLACE FUNCTION create_new_quotation_version(
  p_quotation_id UUID,
  p_items        JSONB,
  p_notes        TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id       UUID;
  v_status          TEXT;
  v_next_version    INT;
  v_version_id      UUID;
  v_subtotal        BIGINT := 0;
  v_discount        BIGINT := 0;
  v_tax             BIGINT := 0;
  v_total           BIGINT := 0;
  v_item            JSONB;
  v_item_unit_price BIGINT;
  v_item_qty        NUMERIC;
  v_item_discount   BIGINT;
  v_item_tax        BIGINT;
  v_item_subtotal   BIGINT;
  v_kind            TEXT;
BEGIN
  SELECT q.tenant_id, q.status
    INTO v_tenant_id, v_status
    FROM quotations q
   WHERE q.id = p_quotation_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Orçamento não encontrado.'
      USING ERRCODE = 'P0001';
  END IF;

  -- Pertencimento ao tenant
  IF NOT EXISTS (
    SELECT 1 FROM tenant_memberships
     WHERE user_id   = auth.uid()
       AND tenant_id = v_tenant_id
       AND status    = 'active'
  ) THEN
    RAISE EXCEPTION 'Sem permissão para versionar este orçamento.'
      USING ERRCODE = '42501';
  END IF;

  -- Permissão
  IF NOT has_permission('quotations.write') THEN
    RAISE EXCEPTION 'Permissão quotations.write necessária.'
      USING ERRCODE = '42501';
  END IF;

  -- Bloqueia status terminal
  IF v_status IN ('approved', 'rejected', 'expired', 'cancelled') THEN
    RAISE EXCEPTION 'Não é possível criar nova versão para orçamento no status "%".', v_status
      USING ERRCODE = 'P0001';
  END IF;

  -- Próximo número de versão
  SELECT COALESCE(MAX(version_number), 0) + 1
    INTO v_next_version
    FROM quotation_versions
   WHERE quotation_id = p_quotation_id;

  -- Cria versão
  INSERT INTO quotation_versions(quotation_id, version_number, notes, created_by)
  VALUES (p_quotation_id, v_next_version, p_notes, auth.uid())
  RETURNING id INTO v_version_id;

  -- Processa itens
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_kind            := COALESCE(v_item->>'kind', 'service');
    v_item_unit_price := COALESCE((v_item->>'unit_price_cents')::BIGINT, 0);
    v_item_qty        := COALESCE((v_item->>'quantity')::NUMERIC, 1);
    v_item_discount   := COALESCE((v_item->>'discount_cents')::BIGINT, 0);
    v_item_tax        := COALESCE((v_item->>'tax_cents')::BIGINT, 0);
    v_item_subtotal   := ROUND(v_item_unit_price * v_item_qty)::BIGINT - v_item_discount + v_item_tax;

    INSERT INTO quotation_items(
      quotation_id, version_id, kind, description,
      quantity, unit_price_cents, discount_cents, tax_cents, subtotal_cents
    ) VALUES (
      p_quotation_id,
      v_version_id,
      v_kind,
      COALESCE(v_item->>'description', ''),
      v_item_qty,
      v_item_unit_price,
      v_item_discount,
      v_item_tax,
      v_item_subtotal
    );

    v_subtotal := v_subtotal + ROUND(v_item_unit_price * v_item_qty)::BIGINT;
    v_discount := v_discount + v_item_discount;
    v_tax      := v_tax      + v_item_tax;
    v_total    := v_total    + v_item_subtotal;
  END LOOP;

  -- Atualiza totais na versão
  UPDATE quotation_versions
     SET subtotal_cents = v_subtotal,
         discount_cents = v_discount,
         tax_cents      = v_tax,
         total_cents    = v_total
   WHERE id = v_version_id;

  -- Promove versão corrente e volta ao rascunho se necessário
  UPDATE quotations
     SET current_version_id = v_version_id,
         status = CASE
                    WHEN status IN ('under_review', 'change_requested') THEN 'draft'
                    ELSE status
                  END,
         updated_at = now()
   WHERE id = p_quotation_id;

  -- Log de status no histórico
  INSERT INTO quotation_status_history(tenant_id, quotation_id, status, notes, changed_by)
  SELECT v_tenant_id, p_quotation_id, 'draft', 'Nova versão ' || v_next_version || ' criada', auth.uid()
  WHERE v_status IN ('under_review', 'change_requested');

  -- Auditoria
  PERFORM log_audit(
    v_tenant_id,
    'quotation.new_version_created',
    'quotations',
    p_quotation_id::text,
    NULL,
    jsonb_build_object(
      'version_id',     v_version_id,
      'version_number', v_next_version,
      'total_cents',    v_total
    )
  );

  RETURN jsonb_build_object(
    'version_id',     v_version_id,
    'version_number', v_next_version,
    'total_cents',    v_total
  );
END;
$$;

COMMENT ON FUNCTION create_new_quotation_version(UUID, JSONB, TEXT) IS
  'Cria nova versão de orçamento com itens. Exige quotations.write. Emite log_audit.';

-- ── 4. Auditar create_return_work_order ───────────────────────────────────────

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
  v_tenant_id   UUID;
  v_orig        RECORD;
  v_new_id      UUID;
  v_customer    TEXT;
BEGIN
  SELECT wo.tenant_id, wo.status, wo.title, wo.customer_id
    INTO v_orig
    FROM work_orders wo
   WHERE wo.id = p_original_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'OS não encontrada.'
      USING ERRCODE = 'P0001';
  END IF;

  v_tenant_id := v_orig.tenant_id;

  -- Pertencimento ao tenant
  IF NOT EXISTS (
    SELECT 1 FROM tenant_memberships
     WHERE user_id   = auth.uid()
       AND tenant_id = v_tenant_id
       AND status    = 'active'
  ) THEN
    RAISE EXCEPTION 'Sem permissão para criar retorno.'
      USING ERRCODE = '42501';
  END IF;

  -- Permissão
  IF NOT has_permission('work_orders.manage') THEN
    RAISE EXCEPTION 'Permissão work_orders.manage necessária para criar retorno.'
      USING ERRCODE = '42501';
  END IF;

  -- Apenas OS concluída pode gerar retorno
  IF v_orig.status <> 'done' THEN
    RAISE EXCEPTION 'Retorno só pode ser criado para OS com status "done". Status atual: "%".', v_orig.status
      USING ERRCODE = 'P0001';
  END IF;

  IF trim(COALESCE(p_reason, '')) = '' THEN
    RAISE EXCEPTION 'Informe o motivo do retorno.'
      USING ERRCODE = 'P0001';
  END IF;

  -- Nome do cliente
  SELECT name INTO v_customer FROM customers WHERE id = v_orig.customer_id;

  -- Cria OS de retorno
  INSERT INTO work_orders(tenant_id, customer_id, title, status, parent_work_order_id, created_by)
  VALUES (
    v_tenant_id,
    v_orig.customer_id,
    '[Retorno] ' || v_orig.title,
    'opened',
    p_original_id,
    auth.uid()
  )
  RETURNING id INTO v_new_id;

  -- Evento na OS original
  INSERT INTO work_order_events(tenant_id, work_order_id, event_type, notes, created_by)
  VALUES (v_tenant_id, p_original_id, 'return_created', trim(p_reason), auth.uid());

  -- Evento na nova OS
  INSERT INTO work_order_events(tenant_id, work_order_id, event_type, notes, created_by)
  VALUES (v_tenant_id, v_new_id, 'created', 'Retorno de OS ' || p_original_id::text, auth.uid());

  -- Auditoria
  PERFORM log_audit(
    v_tenant_id,
    'work_order.return_created',
    'work_orders',
    v_new_id::text,
    NULL,
    jsonb_build_object(
      'original_work_order_id', p_original_id,
      'reason', trim(p_reason)
    )
  );

  RETURN jsonb_build_object(
    'id',           v_new_id,
    'title',        '[Retorno] ' || v_orig.title,
    'status',       'opened',
    'customer_id',  v_orig.customer_id,
    'customer_name', v_customer,
    'parent_work_order_id', p_original_id,
    'tenant_id',    v_tenant_id
  );
END;
$$;

COMMENT ON FUNCTION create_return_work_order(UUID, TEXT) IS
  'Cria OS de retorno a partir de OS concluída. Exige work_orders.manage. Emite log_audit.';

-- ── 5. RPC list_audit_events — para tela Flutter de auditoria ────────────────

CREATE OR REPLACE FUNCTION list_audit_events(
  p_limit  INT     DEFAULT 50,
  p_entity TEXT    DEFAULT NULL,
  p_action TEXT    DEFAULT NULL
)
RETURNS TABLE (
  id          UUID,
  action      TEXT,
  entity      TEXT,
  entity_id   TEXT,
  actor_id    UUID,
  after_data  JSONB,
  metadata    JSONB,
  created_at  TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id UUID;
BEGIN
  v_tenant_id := current_tenant_id();

  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'Tenant não identificado.'
      USING ERRCODE = '42501';
  END IF;

  IF NOT has_permission('audit.read') THEN
    RAISE EXCEPTION 'Permissão audit.read necessária.'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    al.id,
    al.action,
    al.entity,
    al.entity_id,
    al.actor_id,
    al.after_data,
    al.metadata,
    al.created_at
  FROM audit_logs al
  WHERE al.tenant_id = v_tenant_id
    AND (p_entity IS NULL OR al.entity = p_entity)
    AND (p_action IS NULL OR al.action ILIKE '%' || p_action || '%')
  ORDER BY al.created_at DESC
  LIMIT LEAST(p_limit, 200);
END;
$$;

COMMENT ON FUNCTION list_audit_events(INT, TEXT, TEXT) IS
  'Lista eventos de auditoria do tenant. Exige audit.read. Máximo 200 registros.';

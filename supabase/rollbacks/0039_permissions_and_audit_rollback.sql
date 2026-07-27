-- Rollback: 0039_permissions_and_audit
--
-- ##########################################################################
-- # AVISO DE SEGURANCA — LEIA ANTES DE EXECUTAR
-- #
-- # 0039 nao foi apenas uma adicao de recursos: ela CORRIGIU UMA FALHA.
-- # Antes de 0039, cancel_quotation e cancel_work_order verificavam apenas se
-- # o usuario pertencia ao tenant, sem checar a permissao especifica
-- # (quotations.write / work_orders.manage). Qualquer membro do tenant podia
-- # cancelar orcamentos e OS.
-- #
-- # ESTE ROLLBACK REINTRODUZ ESSA FALHA, porque restaura as versoes antigas
-- # das funcoes. Alem disso, remove as chamadas log_audit adicionadas em 0039,
-- # entao cancelamentos, novas versoes e retornos deixam de ser auditados.
-- #
-- # Use apenas em ambiente de desenvolvimento, ou em producao como medida
-- # emergencial de curtissima duracao, com plano de reaplicar 0039.
-- ##########################################################################
--
-- O que este script faz:
--   1. Remove list_audit_events (funcao nova de 0039).
--   2. Restaura as versoes de 0036/0037/0038 das quatro funcoes substituidas.
--
-- As definicoes abaixo foram extraidas literalmente de 0036, 0037 e 0038.
-- Se aquelas migrations mudarem, este arquivo precisa ser regerado.

DROP FUNCTION IF EXISTS list_audit_events(int, text, text);

-- ══════════════════════════════════════════════════════════════════════════
-- Restaura de 0036_cancellations.sql: cancel_quotation, cancel_work_order
-- ══════════════════════════════════════════════════════════════════════════

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
  SELECT tenant_id, status
    INTO v_tenant_id, v_status
    FROM quotations
   WHERE id = p_quotation_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Orçamento não encontrado.'
      USING ERRCODE = 'P0001';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM tenant_members
     WHERE user_id   = auth.uid()
       AND tenant_id = v_tenant_id
       AND is_active = TRUE
  ) THEN
    RAISE EXCEPTION 'Sem permissão para cancelar este orçamento.'
      USING ERRCODE = '42501';
  END IF;

  IF v_status IN ('approved', 'cancelled') THEN
    RAISE EXCEPTION 'Orçamento não pode ser cancelado no status "%".', v_status
      USING ERRCODE = 'P0001';
  END IF;

  IF trim(COALESCE(p_reason, '')) = '' THEN
    RAISE EXCEPTION 'Informe o motivo do cancelamento.'
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE quotations
     SET status              = 'cancelled',
         cancelled_at        = now(),
         cancellation_reason = trim(p_reason),
         updated_at          = now()
   WHERE id = p_quotation_id;

  INSERT INTO quotation_status_history(tenant_id, quotation_id, status, notes, changed_by)
  VALUES (v_tenant_id, p_quotation_id, 'cancelled', trim(p_reason), auth.uid());
END;
$$;

COMMENT ON FUNCTION cancel_quotation(UUID, TEXT) IS
  'Cancela um orçamento com motivo obrigatório. Bloqueado para status approved e cancelled.';

-- ── RPC: cancel_work_order ────────────────────────────────────────────────────

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

  IF NOT EXISTS (
    SELECT 1 FROM tenant_members
     WHERE user_id   = auth.uid()
       AND tenant_id = v_tenant_id
       AND is_active = TRUE
  ) THEN
    RAISE EXCEPTION 'Sem permissão para cancelar esta OS.'
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

  -- event_type 'cancelled' é um dos valores permitidos no CHECK
  INSERT INTO work_order_events(tenant_id, work_order_id, event_type, notes, created_by)
  VALUES (v_tenant_id, p_work_order_id, 'cancelled', trim(p_reason), auth.uid());
END;
$$;

COMMENT ON FUNCTION cancel_work_order(UUID, TEXT) IS
  'Cancela uma OS com motivo obrigatório. Bloqueado para status done e cancelled.';

-- ══════════════════════════════════════════════════════════════════════════
-- Restaura de 0037_quotation_versioning.sql: create_new_quotation_version
-- ══════════════════════════════════════════════════════════════════════════

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
  v_next_version    INTEGER;
  v_version_id      UUID;
  v_item            JSONB;
  v_kind            TEXT;
  v_quantity        NUMERIC;
  v_unit_price      INTEGER;
  v_unit_cost       INTEGER;
  v_total           INTEGER;
  v_subtotal        INTEGER := 0;
  v_discount        INTEGER := 0;
  v_tax             INTEGER := 0;
  v_cost            INTEGER := 0;
BEGIN
  SELECT tenant_id, status
    INTO v_tenant_id, v_status
    FROM quotations
   WHERE id = p_quotation_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Orçamento não encontrado.'
      USING ERRCODE = 'P0001';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM tenant_members
     WHERE user_id   = auth.uid()
       AND tenant_id = v_tenant_id
       AND is_active = TRUE
  ) THEN
    RAISE EXCEPTION 'Sem permissão para revisar este orçamento.'
      USING ERRCODE = '42501';
  END IF;

  IF NOT has_permission('quotations.write') THEN
    RAISE EXCEPTION 'Permissão insuficiente para criar versão de orçamento.'
      USING ERRCODE = '42501';
  END IF;

  IF v_status IN ('approved', 'rejected', 'expired', 'cancelled') THEN
    RAISE EXCEPTION 'Orçamento no status "%" não pode ser revisado.', v_status
      USING ERRCODE = 'P0001';
  END IF;

  IF jsonb_typeof(p_items) <> 'array' OR jsonb_array_length(p_items) = 0 THEN
    RAISE EXCEPTION 'Inclua ao menos um item na nova versão.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- Próximo número de versão
  SELECT COALESCE(MAX(version_number), 0) + 1
    INTO v_next_version
    FROM quotation_versions
   WHERE quotation_id = p_quotation_id;

  -- Cria a versão (totais calculados abaixo)
  INSERT INTO quotation_versions(tenant_id, quotation_id, version_number, created_by)
  VALUES (v_tenant_id, p_quotation_id, v_next_version, auth.uid())
  RETURNING id INTO v_version_id;

  -- Insere os itens e acumula totais
  FOR v_item IN SELECT * FROM jsonb_array_elements(p_items)
  LOOP
    v_kind       := v_item->>'kind';
    v_quantity   := COALESCE((v_item->>'quantity')::NUMERIC, 0);
    v_unit_price := COALESCE((v_item->>'unit_price_cents')::INTEGER, 0);
    v_unit_cost  := COALESCE((v_item->>'unit_cost_cents')::INTEGER, 0);
    v_total      := ROUND(v_quantity * v_unit_price);

    IF v_quantity <= 0 OR v_unit_price < 0 OR v_unit_cost < 0 THEN
      RAISE EXCEPTION 'Item de orçamento inválido.'
        USING ERRCODE = 'check_violation';
    END IF;

    IF v_kind = 'discount' THEN
      v_discount := v_discount + v_total;
    ELSIF v_kind = 'tax' THEN
      v_tax := v_tax + v_total;
    ELSE
      v_subtotal := v_subtotal + v_total;
    END IF;
    v_cost := v_cost + ROUND(v_quantity * v_unit_cost);

    INSERT INTO quotation_items(
      tenant_id, quotation_id, version_id, kind, description,
      quantity, unit_price_cents, unit_cost_cents, total_cents
    ) VALUES (
      v_tenant_id, p_quotation_id, v_version_id, v_kind,
      LEFT(TRIM(v_item->>'description'), 300),
      v_quantity, v_unit_price, v_unit_cost, v_total
    );
  END LOOP;

  -- Atualiza totais da versão
  UPDATE quotation_versions
     SET subtotal_cents      = v_subtotal,
         discount_cents      = v_discount,
         tax_cents           = v_tax,
         total_cents         = GREATEST(v_subtotal + v_tax - v_discount, 0),
         internal_cost_cents = v_cost,
         gross_margin_cents  = GREATEST(v_subtotal + v_tax - v_discount, 0) - v_cost,
         snapshot            = jsonb_build_object('items', p_items)
   WHERE id = v_version_id;

  -- Atualiza orçamento: nova versão corrente + totais recalculados
  UPDATE quotations
     SET current_version_id = v_version_id,
         subtotal_cents     = v_subtotal,
         discount_cents     = v_discount,
         tax_cents          = v_tax,
         total_cents        = GREATEST(v_subtotal + v_tax - v_discount, 0),
         -- Volta a draft se estava under_review/change_requested
         status = CASE
           WHEN status IN ('under_review', 'change_requested') THEN 'draft'
           ELSE status
         END,
         updated_at = now()
   WHERE id = p_quotation_id;

  -- Registra no histórico
  INSERT INTO quotation_status_history(tenant_id, quotation_id, status, notes, changed_by)
  SELECT v_tenant_id, p_quotation_id, status,
         'Nova versão ' || v_next_version || COALESCE(': ' || p_notes, ''),
         auth.uid()
    FROM quotations WHERE id = p_quotation_id;

  RETURN jsonb_build_object(
    'version_id',     v_version_id,
    'version_number', v_next_version,
    'total_cents',    GREATEST(v_subtotal + v_tax - v_discount, 0)
  );
END;
$$;

COMMENT ON FUNCTION create_new_quotation_version(UUID, JSONB, TEXT) IS
  'Cria nova versão do orçamento com os itens fornecidos. Bloqueado em status terminais.';

-- ══════════════════════════════════════════════════════════════════════════
-- Restaura de 0038_work_order_returns.sql: create_return_work_order
-- ══════════════════════════════════════════════════════════════════════════

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

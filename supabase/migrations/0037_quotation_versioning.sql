-- ============================================================
-- 0037_quotation_versioning.sql
-- Versionamento completo de orçamentos:
--   create_new_quotation_version() — clona versão atual com novos itens
--   list_quotation_versions()      — lista versões para o seletor de UI
-- ============================================================

-- ── RPC: create_new_quotation_version ────────────────────────────────────────
--
-- Cria uma nova versão do orçamento a partir dos itens fornecidos.
-- Atualiza current_version_id e recalcula os totais no orçamento pai.
-- Status permitidos para revisão: draft, under_review, sent, viewed,
-- awaiting_approval, change_requested.
-- Bloqueado em: approved, rejected, expired, cancelled.

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

-- ── RPC: list_quotation_versions ─────────────────────────────────────────────

CREATE OR REPLACE FUNCTION list_quotation_versions(p_quotation_id UUID)
RETURNS TABLE (
  id              UUID,
  version_number  INTEGER,
  total_cents     INTEGER,
  subtotal_cents  INTEGER,
  discount_cents  INTEGER,
  tax_cents       INTEGER,
  is_current      BOOLEAN,
  created_at      TIMESTAMPTZ,
  created_by      UUID
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id UUID;
BEGIN
  SELECT tenant_id INTO v_tenant_id
    FROM quotations WHERE id = p_quotation_id;

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
    RAISE EXCEPTION 'Sem permissão para listar versões deste orçamento.'
      USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT
    qv.id,
    qv.version_number,
    qv.total_cents,
    qv.subtotal_cents,
    qv.discount_cents,
    qv.tax_cents,
    qv.id = q.current_version_id AS is_current,
    qv.created_at,
    qv.created_by
  FROM quotation_versions qv
  JOIN quotations q ON q.id = qv.quotation_id
  WHERE qv.quotation_id = p_quotation_id
  ORDER BY qv.version_number DESC;
END;
$$;

COMMENT ON FUNCTION list_quotation_versions(UUID) IS
  'Lista todas as versões de um orçamento em ordem decrescente.';

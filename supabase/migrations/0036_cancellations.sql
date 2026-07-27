-- ============================================================
-- 0036_cancellations.sql
-- Cancelamentos controlados + histórico de status de orçamentos
-- ============================================================

-- ── Colunas de cancelamento ───────────────────────────────────────────────────

ALTER TABLE quotations
  ADD COLUMN IF NOT EXISTS cancelled_at         TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS cancellation_reason  TEXT;

ALTER TABLE work_orders
  ADD COLUMN IF NOT EXISTS cancelled_at         TIMESTAMPTZ,
  ADD COLUMN IF NOT EXISTS cancellation_reason  TEXT;

CREATE INDEX IF NOT EXISTS idx_quotations_cancelled_at
  ON quotations(tenant_id, cancelled_at)
  WHERE cancelled_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_work_orders_cancelled_at
  ON work_orders(tenant_id, cancelled_at)
  WHERE cancelled_at IS NOT NULL;

-- ── Tabela de histórico de status de orçamentos ───────────────────────────────
-- (análoga a work_order_events mas para orçamentos)

CREATE TABLE IF NOT EXISTS quotation_status_history (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  quotation_id  uuid        NOT NULL REFERENCES quotations(id) ON DELETE CASCADE,
  status        text        NOT NULL CHECK (status IN (
                              'draft','under_review','sent','viewed',
                              'awaiting_approval','approved','rejected',
                              'change_requested','expired','cancelled'
                            )),
  notes         text        CHECK (notes IS NULL OR char_length(notes) <= 1000),
  changed_by    uuid        REFERENCES auth.users(id),
  changed_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_quotation_status_history_quotation
  ON quotation_status_history(quotation_id, changed_at DESC);

ALTER TABLE quotation_status_history ENABLE ROW LEVEL SECURITY;

CREATE POLICY "quotation_status_history_select" ON quotation_status_history
  FOR SELECT TO authenticated
  USING (tenant_id = current_tenant_id() AND has_permission('quotations.read'));

-- ── RPC: cancel_quotation ─────────────────────────────────────────────────────

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

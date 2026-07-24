-- =============================================================================
-- Migration: 0010_work_order_acceptance
-- Descricao: Aceite do cliente para ordem de servico — Entrega 7
-- Depende de: 0008_work_orders
-- Rollback: supabase/rollbacks/0010_work_order_acceptance_rollback.sql
-- =============================================================================

CREATE TABLE work_order_acceptances (
  id                      uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id               uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  work_order_id           uuid        NOT NULL REFERENCES work_orders(id) ON DELETE CASCADE,
  signer_name             text        NOT NULL CHECK (char_length(signer_name) BETWEEN 2 AND 160),
  signer_document_partial text        CHECK (signer_document_partial IS NULL OR char_length(signer_document_partial) <= 32),
  comments                text        CHECK (comments IS NULL OR char_length(comments) <= 1000),
  accepted_at             timestamptz NOT NULL DEFAULT now(),
  created_by              uuid        REFERENCES auth.users(id),
  CONSTRAINT uq_work_order_acceptance_once UNIQUE (work_order_id)
);

CREATE INDEX idx_work_order_acceptances_work_order
  ON work_order_acceptances (work_order_id);

CREATE OR REPLACE FUNCTION record_work_order_acceptance(
  p_work_order_id uuid,
  p_signer_name text,
  p_signer_document_partial text DEFAULT NULL,
  p_comments text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_work_order work_orders;
  v_acceptance_id uuid;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL OR NOT (has_permission('work_orders.execute') OR has_permission('work_orders.manage')) THEN
    RAISE EXCEPTION 'Permissao insuficiente para registrar aceite.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_work_order
  FROM work_orders
  WHERE id = p_work_order_id AND tenant_id = v_tenant_id;

  IF v_work_order.id IS NULL THEN
    RAISE EXCEPTION 'OS nao encontrada.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_work_order.status = 'cancelled' THEN
    RAISE EXCEPTION 'OS cancelada nao aceita aceite.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF char_length(trim(p_signer_name)) < 2 THEN
    RAISE EXCEPTION 'Responsavel pelo aceite invalido.'
      USING ERRCODE = 'check_violation';
  END IF;

  INSERT INTO work_order_acceptances (
    tenant_id, work_order_id, signer_name, signer_document_partial,
    comments, created_by
  ) VALUES (
    v_tenant_id, p_work_order_id, LEFT(TRIM(p_signer_name), 160),
    NULLIF(LEFT(TRIM(COALESCE(p_signer_document_partial, '')), 32), ''),
    NULLIF(LEFT(TRIM(COALESCE(p_comments, '')), 1000), ''),
    auth.uid()
  )
  ON CONFLICT (work_order_id) DO UPDATE
  SET signer_name = EXCLUDED.signer_name,
      signer_document_partial = EXCLUDED.signer_document_partial,
      comments = EXCLUDED.comments,
      accepted_at = now(),
      created_by = auth.uid()
  RETURNING id INTO v_acceptance_id;

  UPDATE work_orders
  SET status = CASE WHEN status <> 'done' THEN 'done' ELSE status END,
      completed_at = COALESCE(completed_at, now())
  WHERE id = p_work_order_id;

  INSERT INTO work_order_events (
    tenant_id, work_order_id, event_type, notes, created_by
  ) VALUES (
    v_tenant_id, p_work_order_id, 'completed',
    'Aceite registrado por ' || LEFT(TRIM(p_signer_name), 160), auth.uid()
  );

  PERFORM log_audit(
    v_tenant_id,
    'work_order.acceptance.recorded',
    'work_order_acceptances',
    v_acceptance_id::text,
    NULL,
    jsonb_build_object('work_order_id', p_work_order_id, 'signer_name', LEFT(TRIM(p_signer_name), 160))
  );

  RETURN jsonb_build_object('id', v_acceptance_id);
END;
$$;

ALTER TABLE work_order_acceptances ENABLE ROW LEVEL SECURITY;

CREATE POLICY "work_order_acceptances_select" ON work_order_acceptances
  FOR SELECT
  USING (tenant_id = current_tenant_id() AND has_permission('work_orders.read'));

CREATE POLICY "work_order_acceptances_insert" ON work_order_acceptances
  FOR INSERT
  WITH CHECK (has_permission('work_orders.execute') OR has_permission('work_orders.manage'));

CREATE POLICY "work_order_acceptances_update" ON work_order_acceptances
  FOR UPDATE
  USING (
    tenant_id = current_tenant_id()
    AND (has_permission('work_orders.execute') OR has_permission('work_orders.manage'))
  )
  WITH CHECK (
    tenant_id = current_tenant_id()
    AND (has_permission('work_orders.execute') OR has_permission('work_orders.manage'))
  );

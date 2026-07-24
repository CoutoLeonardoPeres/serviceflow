-- =============================================================================
-- Migration: 0012_work_order_evidence_storage
-- Descricao: Storage seguro e RPC para evidencias/anexos de OS — Entrega 7
-- Depende de: 0008_work_orders
-- Rollback: supabase/rollbacks/0012_work_order_evidence_storage_rollback.sql
-- =============================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'work-order-evidence',
  'work-order-evidence',
  false,
  52428800,
  ARRAY['image/jpeg','image/png','image/webp','video/mp4','application/pdf']
)
ON CONFLICT (id) DO UPDATE SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

CREATE POLICY "work_order_evidence_storage_select" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'work-order-evidence'
    AND (storage.foldername(name))[1] = current_tenant_id()::text
    AND has_permission('work_orders.read')
  );

CREATE POLICY "work_order_evidence_storage_insert" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'work-order-evidence'
    AND (storage.foldername(name))[1] = current_tenant_id()::text
    AND has_permission('work_orders.execute')
  );

CREATE OR REPLACE FUNCTION record_work_order_evidence(
  p_work_order_id uuid,
  p_kind text,
  p_storage_path text,
  p_mime_type text,
  p_size_bytes bigint,
  p_checksum text DEFAULT NULL
) RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_work_order work_orders;
  v_evidence_id uuid;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL OR NOT has_permission('work_orders.execute') THEN
    RAISE EXCEPTION 'Permissao insuficiente para registrar evidencia da OS.'
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
    RAISE EXCEPTION 'Nao e permitido anexar evidencia em OS cancelada.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF p_kind NOT IN ('photo','video','document','signature') THEN
    RAISE EXCEPTION 'Tipo de evidencia invalido.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF p_size_bytes <= 0 OR p_size_bytes > 52428800 THEN
    RAISE EXCEPTION 'Arquivo fora do limite permitido.'
      USING ERRCODE = 'check_violation';
  END IF;

  IF p_storage_path IS NULL OR p_storage_path NOT LIKE v_tenant_id::text || '/' || p_work_order_id::text || '/%' THEN
    RAISE EXCEPTION 'Caminho de armazenamento invalido.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  INSERT INTO work_order_evidence (
    tenant_id, work_order_id, kind, storage_path, mime_type, size_bytes,
    checksum, created_by
  ) VALUES (
    v_tenant_id, p_work_order_id, p_kind, p_storage_path, p_mime_type,
    p_size_bytes, p_checksum, auth.uid()
  )
  RETURNING id INTO v_evidence_id;

  INSERT INTO work_order_events (
    tenant_id, work_order_id, event_type, notes, created_by
  ) VALUES (
    v_tenant_id,
    p_work_order_id,
    'note',
    CASE
      WHEN p_kind = 'signature' THEN 'Assinatura anexada ao aceite.'
      ELSE 'Evidencia anexada: ' || p_kind
    END,
    auth.uid()
  );

  PERFORM log_audit(
    v_tenant_id,
    'work_order.evidence.created',
    'work_order_evidence',
    v_evidence_id::text,
    NULL,
    jsonb_build_object(
      'work_order_id', p_work_order_id,
      'kind', p_kind,
      'storage_path', p_storage_path,
      'size_bytes', p_size_bytes
    )
  );

  RETURN jsonb_build_object('id', v_evidence_id);
END;
$$;

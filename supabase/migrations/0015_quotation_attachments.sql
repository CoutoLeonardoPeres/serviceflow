-- =============================================================================
-- Migration: 0015_quotation_attachments
-- Descricao: Fotos privadas de orcamentos para catalogo e historico
-- Depende de: 0005_quotations
-- Rollback: supabase/rollbacks/0015_quotation_attachments_rollback.sql
-- =============================================================================

CREATE TABLE quotation_attachments (
  id            uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id     uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  quotation_id  uuid        NOT NULL REFERENCES quotations(id) ON DELETE CASCADE,
  storage_path  text        NOT NULL CHECK (char_length(storage_path) BETWEEN 10 AND 700),
  mime_type     text        NOT NULL CHECK (mime_type IN ('image/jpeg','image/png','image/webp')),
  size_bytes    bigint      NOT NULL CHECK (size_bytes > 0 AND size_bytes <= 52428800),
  checksum      text        CHECK (checksum IS NULL OR char_length(checksum) BETWEEN 32 AND 128),
  created_at    timestamptz NOT NULL DEFAULT now(),
  uploaded_by   uuid        REFERENCES auth.users(id)
);

CREATE UNIQUE INDEX uq_quotation_attachments_path
  ON quotation_attachments (storage_path);
CREATE INDEX idx_quotation_attachments_quote
  ON quotation_attachments (quotation_id, created_at DESC);

CREATE OR REPLACE FUNCTION _sf_set_quotation_attachment_meta()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY INVOKER
SET search_path = public
AS $$
BEGIN
  SELECT tenant_id INTO NEW.tenant_id
  FROM quotations
  WHERE id = NEW.quotation_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Orcamento nao encontrado ou sem acesso: %', NEW.quotation_id
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF TG_OP = 'INSERT' THEN
    NEW.uploaded_by := auth.uid();
  ELSE
    NEW.tenant_id := OLD.tenant_id;
  END IF;

  RETURN NEW;
END;
$$;

CREATE TRIGGER trg_quotation_attachments_meta
  BEFORE INSERT OR UPDATE ON quotation_attachments
  FOR EACH ROW EXECUTE FUNCTION _sf_set_quotation_attachment_meta();

ALTER TABLE quotation_attachments ENABLE ROW LEVEL SECURITY;

CREATE POLICY "quotation_attachments_select" ON quotation_attachments
  FOR SELECT TO authenticated
  USING (tenant_id = current_tenant_id() AND has_permission('quotations.read'));

CREATE POLICY "quotation_attachments_insert" ON quotation_attachments
  FOR INSERT TO authenticated
  WITH CHECK (has_permission('quotations.write'));

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'quotation-attachments',
  'quotation-attachments',
  false,
  52428800,
  ARRAY['image/jpeg','image/png','image/webp']
)
ON CONFLICT (id) DO UPDATE
SET
  public = EXCLUDED.public,
  file_size_limit = EXCLUDED.file_size_limit,
  allowed_mime_types = EXCLUDED.allowed_mime_types;

CREATE POLICY "quotation_storage_select" ON storage.objects
  FOR SELECT TO authenticated
  USING (
    bucket_id = 'quotation-attachments'
    AND (storage.foldername(name))[1] = current_tenant_id()::text
    AND has_permission('quotations.read')
  );

CREATE POLICY "quotation_storage_insert" ON storage.objects
  FOR INSERT TO authenticated
  WITH CHECK (
    bucket_id = 'quotation-attachments'
    AND (storage.foldername(name))[1] = current_tenant_id()::text
    AND has_permission('quotations.write')
  );

DROP POLICY IF EXISTS "quotation_storage_insert" ON storage.objects;
DROP POLICY IF EXISTS "quotation_storage_select" ON storage.objects;
DELETE FROM storage.buckets WHERE id = 'quotation-attachments';
DROP POLICY IF EXISTS "quotation_attachments_insert" ON quotation_attachments;
DROP POLICY IF EXISTS "quotation_attachments_select" ON quotation_attachments;
DROP TRIGGER IF EXISTS trg_quotation_attachments_meta ON quotation_attachments;
DROP FUNCTION IF EXISTS _sf_set_quotation_attachment_meta();
DROP TABLE IF EXISTS quotation_attachments;

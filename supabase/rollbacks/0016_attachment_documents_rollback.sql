-- =============================================================================
-- Rollback: 0016_attachment_documents
-- =============================================================================

ALTER TABLE quotation_attachments
  DROP CONSTRAINT IF EXISTS quotation_attachments_mime_type_check;

ALTER TABLE quotation_attachments
  ADD CONSTRAINT quotation_attachments_mime_type_check
  CHECK (
    mime_type IN (
      'image/jpeg',
      'image/png',
      'image/webp'
    )
  );

UPDATE storage.buckets
SET allowed_mime_types = ARRAY['image/jpeg','image/png','image/webp']
WHERE id = 'quotation-attachments';

UPDATE storage.buckets
SET allowed_mime_types = ARRAY[
  'image/jpeg',
  'image/png',
  'image/webp',
  'video/mp4',
  'application/pdf'
]
WHERE id = 'work-order-evidence';

DROP FUNCTION IF EXISTS record_work_order_evidence(uuid, text, text, text, bigint, text);
DROP POLICY IF EXISTS "work_order_evidence_storage_insert" ON storage.objects;
DROP POLICY IF EXISTS "work_order_evidence_storage_select" ON storage.objects;
DELETE FROM storage.buckets WHERE id = 'work-order-evidence';

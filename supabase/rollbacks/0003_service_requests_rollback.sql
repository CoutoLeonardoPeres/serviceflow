DROP POLICY IF EXISTS "service_request_storage_insert" ON storage.objects;
DROP POLICY IF EXISTS "service_request_storage_select" ON storage.objects;

DELETE FROM storage.buckets WHERE id = 'service-request-attachments';

DROP POLICY IF EXISTS "service_request_assignments_update" ON service_request_assignments;
DROP POLICY IF EXISTS "service_request_assignments_insert" ON service_request_assignments;
DROP POLICY IF EXISTS "service_request_assignments_select" ON service_request_assignments;
DROP POLICY IF EXISTS "service_request_notes_insert" ON service_request_notes;
DROP POLICY IF EXISTS "service_request_notes_select" ON service_request_notes;
DROP POLICY IF EXISTS "service_request_attachments_insert" ON service_request_attachments;
DROP POLICY IF EXISTS "service_request_attachments_select" ON service_request_attachments;
DROP POLICY IF EXISTS "service_request_status_history_select" ON service_request_status_history;
DROP POLICY IF EXISTS "service_requests_update" ON service_requests;
DROP POLICY IF EXISTS "service_requests_insert" ON service_requests;
DROP POLICY IF EXISTS "service_requests_select" ON service_requests;
DROP POLICY IF EXISTS "service_priorities_update" ON service_priorities;
DROP POLICY IF EXISTS "service_priorities_insert" ON service_priorities;
DROP POLICY IF EXISTS "service_priorities_select" ON service_priorities;
DROP POLICY IF EXISTS "service_categories_update" ON service_categories;
DROP POLICY IF EXISTS "service_categories_insert" ON service_categories;
DROP POLICY IF EXISTS "service_categories_select" ON service_categories;

DROP FUNCTION IF EXISTS transition_service_request(uuid, text, text);
DROP FUNCTION IF EXISTS _sf_audit_service_request_change();
DROP FUNCTION IF EXISTS _sf_record_service_request_status_history();
DROP FUNCTION IF EXISTS _sf_set_service_request_child_meta();
DROP FUNCTION IF EXISTS _sf_set_service_request_meta();
DROP FUNCTION IF EXISTS _sf_set_service_catalog_meta();

DROP TABLE IF EXISTS service_request_assignments;
DROP TABLE IF EXISTS service_request_notes;
DROP TABLE IF EXISTS service_request_attachments;
DROP TABLE IF EXISTS service_request_status_history;
DROP TABLE IF EXISTS service_requests;
DROP TABLE IF EXISTS service_priorities;
DROP TABLE IF EXISTS service_categories;

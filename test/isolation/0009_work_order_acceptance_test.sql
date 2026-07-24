-- Roteiro manual E7 — aceite da OS.
-- Substituir placeholders por UUIDs reais do Supabase.

BEGIN;

-- SELECT set_config('request.jwt.claim.sub', '<USER_UUID_COM_WORK_ORDERS_EXECUTE>', true);
-- SELECT set_config('request.jwt.claim.role', 'authenticated', true);

-- Registrar aceite do cliente.
-- SELECT record_work_order_acceptance(
--   '<WORK_ORDER_UUID>'::uuid,
--   'Maria Cliente',
--   '***.123.456-**',
--   'Serviço conferido no local.'
-- );

-- Conferir aceite e auditoria.
-- SELECT signer_name, signer_document_partial, accepted_at
-- FROM work_order_acceptances
-- WHERE work_order_id = '<WORK_ORDER_UUID>'::uuid;

-- SELECT action, entity, entity_id, created_at
-- FROM audit_logs
-- WHERE action = 'work_order.acceptance.recorded'
-- ORDER BY created_at DESC
-- LIMIT 5;

ROLLBACK;

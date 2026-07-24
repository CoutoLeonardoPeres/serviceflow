-- Roteiro manual E7 — execução de OS.
-- Substituir placeholders por UUIDs reais do Supabase.

BEGIN;

-- SELECT set_config('request.jwt.claim.sub', '<USER_UUID_COM_WORK_ORDERS_EXECUTE>', true);
-- SELECT set_config('request.jwt.claim.role', 'authenticated', true);

-- Registrar horas trabalhadas.
-- SELECT record_work_order_time_entry(
--   '<WORK_ORDER_UUID>'::uuid,
--   now() - interval '2 hours',
--   now(),
--   'Atendimento técnico em campo.'
-- );

-- Registrar material aplicado.
-- SELECT add_work_order_material(
--   '<WORK_ORDER_UUID>'::uuid,
--   'Filtro secador 1/4',
--   1,
--   4500,
--   9000
-- );

-- Conferir auditoria e eventos.
-- SELECT action, entity, entity_id, created_at
-- FROM audit_logs
-- WHERE action IN ('work_order.time_entry.created', 'work_order.material.created')
-- ORDER BY created_at DESC
-- LIMIT 5;

ROLLBACK;

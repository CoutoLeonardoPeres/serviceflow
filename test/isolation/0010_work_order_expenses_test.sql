-- Roteiro manual E7 — despesas da OS.
-- Substituir placeholders por UUIDs reais do Supabase.

BEGIN;

-- SELECT set_config('request.jwt.claim.sub', '<USER_UUID_COM_WORK_ORDERS_EXECUTE>', true);
-- SELECT set_config('request.jwt.claim.role', 'authenticated', true);

-- Registrar despesa operacional.
-- SELECT add_work_order_expense(
--   '<WORK_ORDER_UUID>'::uuid,
--   'parking',
--   2500,
--   'Estacionamento durante atendimento.'
-- );

-- Conferir despesa e auditoria.
-- SELECT kind, amount_cents, description, created_at
-- FROM work_order_expenses
-- WHERE work_order_id = '<WORK_ORDER_UUID>'::uuid
-- ORDER BY created_at DESC;

-- SELECT action, entity, entity_id, created_at
-- FROM audit_logs
-- WHERE action = 'work_order.expense.created'
-- ORDER BY created_at DESC
-- LIMIT 5;

ROLLBACK;

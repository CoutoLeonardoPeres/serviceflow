-- =============================================================================
-- Teste SQL manual: 0014_customer_satisfaction
-- Substitua os UUIDs por dados reais do tenant antes de executar.
-- Execute autenticado como usuario com permissao work_orders.execute ou manage.
-- =============================================================================

-- SELECT record_work_order_satisfaction(
--   '<WORK_ORDER_UUID_DONE>'::uuid,
--   5,
--   'Cliente Teste',
--   'Atendimento excelente.'
-- );

-- SELECT rating, contact_name, comment
-- FROM work_order_satisfaction
-- WHERE work_order_id = '<WORK_ORDER_UUID_DONE>'::uuid;

-- SELECT action
-- FROM audit_logs
-- WHERE action = 'work_order.satisfaction.recorded'
-- ORDER BY created_at DESC
-- LIMIT 1;

-- Esperado:
-- 1. Apenas usuarios do tenant da OS enxergam a satisfacao.
-- 2. Usuario sem work_orders.execute/manage nao registra satisfacao.
-- 3. OS diferente de done gera erro de regra de negocio.
-- 4. Segunda chamada para a mesma OS atualiza a avaliacao existente.

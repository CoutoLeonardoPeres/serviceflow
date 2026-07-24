-- Roteiro manual de isolamento para evidencias da OS.
-- Substitua <WORK_ORDER_UUID> e <TENANT_UUID> por valores reais do ambiente.
-- Execute autenticado como usuario com permissao work_orders.execute.

SELECT record_work_order_evidence(
  '<WORK_ORDER_UUID>'::uuid,
  'photo',
  '<TENANT_UUID>/<WORK_ORDER_UUID>/evidencia-teste.png',
  'image/png',
  1024
);

SELECT id, kind, storage_path
FROM work_order_evidence
WHERE work_order_id = '<WORK_ORDER_UUID>'::uuid
ORDER BY created_at DESC
LIMIT 1;

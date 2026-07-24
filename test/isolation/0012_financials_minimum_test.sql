-- Roteiro manual de isolamento para financeiro minimo.
-- Substitua <WORK_ORDER_UUID> e <RECEIVABLE_UUID> por valores reais.
-- Execute autenticado como usuario com permissao financials.write.

SELECT create_receivable_from_work_order('<WORK_ORDER_UUID>'::uuid, CURRENT_DATE);

SELECT id, description, amount_cents, balance_cents, status
FROM receivables
WHERE work_order_id = '<WORK_ORDER_UUID>'::uuid;

SELECT register_manual_payment(
  '<RECEIVABLE_UUID>'::uuid,
  'pix_manual',
  1000,
  'PIX-TESTE',
  'Pagamento manual de teste'
);

SELECT r.status, r.balance_cents, p.amount_cents, rc.number
FROM receivables r
JOIN payment_records p ON p.receivable_id = r.id
JOIN receipts rc ON rc.payment_id = p.id
WHERE r.id = '<RECEIVABLE_UUID>'::uuid
ORDER BY p.paid_at DESC
LIMIT 1;

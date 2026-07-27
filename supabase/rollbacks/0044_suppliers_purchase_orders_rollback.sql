-- Rollback: 0044_suppliers_purchase_orders
--
-- ATENCAO — ordem de rollback:
--   Rode este script ANTES de 0042_stock_ledger_rollback.sql. purchase_orders
--   referencia warehouses e purchase_order_items referencia products; se 0042
--   cair primeiro, os FKs quebram.
--
-- PERDA DE DADOS: apaga fornecedores, pedidos e itens. As entradas de estoque
-- ja geradas pelos recebimentos PERMANECEM em stock_movements — a mercadoria
-- entrou de fato e o razao e append-only. Depois deste rollback, esses
-- movimentos ficam com related_entity = 'purchase_orders' apontando para
-- pedidos que nao existem mais. O saldo continua correto; perde-se a
-- rastreabilidade da origem.
--
-- Faca dump de purchase_orders e purchase_order_items antes de rodar em
-- ambiente com dados reais.

DROP FUNCTION IF EXISTS list_purchase_order_items(uuid);
DROP FUNCTION IF EXISTS cancel_purchase_order(uuid, text);
DROP FUNCTION IF EXISTS receive_purchase_order(uuid, jsonb);
DROP FUNCTION IF EXISTS send_purchase_order(uuid);
DROP FUNCTION IF EXISTS create_purchase_order(uuid, uuid, jsonb, date, text);

DROP POLICY IF EXISTS "purchase_order_items_select" ON purchase_order_items;
DROP POLICY IF EXISTS "purchase_orders_select"      ON purchase_orders;
DROP POLICY IF EXISTS "suppliers_update"            ON suppliers;
DROP POLICY IF EXISTS "suppliers_insert"            ON suppliers;
DROP POLICY IF EXISTS "suppliers_select"            ON suppliers;

DROP TABLE IF EXISTS purchase_order_items;

DROP TRIGGER IF EXISTS trg_purchase_orders_updated_at ON purchase_orders;
DROP TABLE IF EXISTS purchase_orders;

DROP TRIGGER IF EXISTS trg_suppliers_updated_at ON suppliers;
DROP TABLE IF EXISTS suppliers;

-- Remove permissoes e grants (ON DELETE CASCADE cuida de role_permissions).
DELETE FROM permissions
WHERE key IN ('purchases.read','purchases.write','purchases.receive');

-- Sequencia de numeracao dos pedidos.
DELETE FROM tenant_sequences WHERE kind = 'purchase_order';

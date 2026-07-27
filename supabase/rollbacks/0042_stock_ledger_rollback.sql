-- Rollback: 0042_stock_ledger
--
-- PERDA DE DADOS TOTAL DO MODULO DE ESTOQUE: apaga catalogo de produtos,
-- depositos, saldos e todo o razao de movimentos. O razao e a unica fonte
-- historica de como o saldo chegou onde esta — nao ha como reconstruir depois.
-- Faca dump de stock_movements antes de rodar isto em qualquer ambiente com
-- dados reais.
--
-- Nao afeta work_order_materials: em F3-P1 o consumo da OS ainda nao gera
-- movimento (ADR-016 so e implementado em F3-P2).

DROP FUNCTION IF EXISTS list_stock_balances(uuid, boolean);
DROP FUNCTION IF EXISTS record_stock_adjustment(uuid, uuid, numeric, text);
DROP FUNCTION IF EXISTS record_stock_exit(uuid, uuid, numeric, text, text, uuid);
DROP FUNCTION IF EXISTS record_stock_entry(uuid, uuid, numeric, integer, text, text, uuid);
DROP FUNCTION IF EXISTS _sf_validate_stock_target(uuid, uuid, uuid);
DROP FUNCTION IF EXISTS _sf_lock_stock_balance(uuid, uuid, uuid);

DROP POLICY IF EXISTS "stock_movements_select" ON stock_movements;
DROP POLICY IF EXISTS "stock_balances_select"  ON stock_balances;
DROP POLICY IF EXISTS "warehouses_update"      ON warehouses;
DROP POLICY IF EXISTS "warehouses_insert"      ON warehouses;
DROP POLICY IF EXISTS "warehouses_select"      ON warehouses;
DROP POLICY IF EXISTS "products_update"        ON products;
DROP POLICY IF EXISTS "products_insert"        ON products;
DROP POLICY IF EXISTS "products_select"        ON products;

DROP TABLE IF EXISTS stock_movements;
DROP TABLE IF EXISTS stock_balances;

DROP TRIGGER IF EXISTS trg_warehouses_updated_at ON warehouses;
DROP TABLE IF EXISTS warehouses;

DROP TRIGGER IF EXISTS trg_products_updated_at ON products;
DROP TABLE IF EXISTS products;

-- stock_average_unit_cost_cents so e usada pelo modulo de estoque.
DROP FUNCTION IF EXISTS stock_average_unit_cost_cents(numeric, bigint);

-- Remove as permissoes e os grants criados em 0042.
-- ON DELETE CASCADE em role_permissions cuida dos vinculos.
DELETE FROM permissions WHERE key IN ('stock.read','stock.write','stock.adjust');

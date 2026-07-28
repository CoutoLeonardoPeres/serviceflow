-- Rollback: 0059_material_catalog_suppliers
--
-- **PERDE DADOS.** Diferente dos rollbacks anteriores desta série, este
-- descarta informação que só existe aqui:
--   * todas as categorias de material e a associação fornecedor↔categoria;
--   * toda a tabela de preços por fornecedor e o histórico de preços;
--   * os campos de endereço, prazo, condição de pagamento e pedido mínimo dos
--     fornecedores já cadastrados;
--   * a categoria, o código de barras, a marca e a margem dos produtos.
--
-- Exporte antes se houver qualquer cadastro real:
--   \copy (SELECT * FROM supplier_products) TO 'supplier_products.csv' CSV HEADER
--   \copy (SELECT * FROM supplier_price_history) TO 'price_history.csv' CSV HEADER
--   \copy (SELECT * FROM material_categories) TO 'categories.csv' CSV HEADER
--   \copy (SELECT id, name, city, state, lead_time_days, payment_terms,
--                min_order_cents FROM suppliers) TO 'suppliers.csv' CSV HEADER
--
-- `products.category_id` referencia `material_categories`, então a ordem
-- abaixo importa: a coluna sai antes da tabela.

DROP FUNCTION IF EXISTS seed_material_categories(uuid);
DROP FUNCTION IF EXISTS best_price_for_product(uuid);

DROP TRIGGER IF EXISTS trg_supplier_price_history ON supplier_products;
DROP FUNCTION IF EXISTS _sf_log_supplier_price();

DROP TABLE IF EXISTS supplier_price_history;
DROP TABLE IF EXISTS supplier_products;
DROP TABLE IF EXISTS supplier_categories;

ALTER TABLE products
  DROP COLUMN IF EXISTS category_id,
  DROP COLUMN IF EXISTS barcode,
  DROP COLUMN IF EXISTS brand,
  DROP COLUMN IF EXISTS markup_percent;

DROP TABLE IF EXISTS material_categories;

ALTER TABLE suppliers
  DROP COLUMN IF EXISTS state_registration,
  DROP COLUMN IF EXISTS contact_name,
  DROP COLUMN IF EXISTS whatsapp,
  DROP COLUMN IF EXISTS website,
  DROP COLUMN IF EXISTS zip_code,
  DROP COLUMN IF EXISTS street,
  DROP COLUMN IF EXISTS number,
  DROP COLUMN IF EXISTS complement,
  DROP COLUMN IF EXISTS district,
  DROP COLUMN IF EXISTS city,
  DROP COLUMN IF EXISTS state,
  DROP COLUMN IF EXISTS lead_time_days,
  DROP COLUMN IF EXISTS payment_terms,
  DROP COLUMN IF EXISTS min_order_cents,
  DROP COLUMN IF EXISTS delivers;

ALTER TABLE tenant_settings
  DROP COLUMN IF EXISTS default_markup_percent;

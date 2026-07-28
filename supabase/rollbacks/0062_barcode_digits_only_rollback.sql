-- Rollback: 0062_barcode_digits_only
--
-- **Não desfaz a limpeza de dados.** Códigos de barras inválidos que a 0062
-- transformou em NULL não voltam — a informação original já estava perdida
-- (era notação científica, não código).
--
-- Reverter reintroduz o defeito: uma planilha em que o Excel converteu o
-- código de barras para 7,89123E+12 volta a ser gravada como se fosse código.
--
-- ATENÇÃO: restaura a versão 0060 de `import_supplier_prices` (sem a guarda
-- de código de barras). Rodar 0060 de novo é alternativa equivalente.

ALTER TABLE products DROP CONSTRAINT IF EXISTS products_barcode_check;
ALTER TABLE products
  ADD CONSTRAINT products_barcode_check
  CHECK (barcode IS NULL OR char_length(barcode) BETWEEN 6 AND 20);

DROP FUNCTION IF EXISTS _sf_clean_barcode(text);

-- Reaplique supabase/migrations/0060_supplier_price_import.sql para restaurar
-- a versão anterior de import_supplier_prices.

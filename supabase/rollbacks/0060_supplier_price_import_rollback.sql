-- Rollback: 0060_supplier_price_import
--
-- Sem perda de dados: os preços já importados continuam em
-- `supplier_products`, e o histórico marcado como `spreadsheet` continua em
-- `supplier_price_history`. O que some é a possibilidade de importar — volta
-- a valer só a digitação item a item.
--
-- Não substitui nenhuma função anterior, então não depende de ordem em
-- relação à 0059 (embora a 0059 seja quem cria as tabelas que esta usa).

DROP FUNCTION IF EXISTS import_supplier_prices(uuid, jsonb, boolean);

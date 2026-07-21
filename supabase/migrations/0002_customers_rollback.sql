-- =============================================================================
-- Rollback: 0002_customers
-- Desfaz COMPLETAMENTE a migration 0002_customers.
-- ATENÇÃO: apaga todos os dados de clientes, contatos, endereços e ativos.
-- =============================================================================

-- Remover triggers e funções
DROP TRIGGER IF EXISTS trg_customers_audit         ON customers;
DROP TRIGGER IF EXISTS trg_customer_assets_meta    ON customer_assets;
DROP TRIGGER IF EXISTS trg_customer_addresses_meta ON customer_addresses;
DROP TRIGGER IF EXISTS trg_customer_contacts_meta  ON customer_contacts;
DROP TRIGGER IF EXISTS trg_customers_meta          ON customers;

DROP TRIGGER IF EXISTS trg_customer_assets_updated_at    ON customer_assets;
DROP TRIGGER IF EXISTS trg_customer_addresses_updated_at ON customer_addresses;
DROP TRIGGER IF EXISTS trg_customer_contacts_updated_at  ON customer_contacts;
DROP TRIGGER IF EXISTS trg_customers_updated_at          ON customers;

DROP FUNCTION IF EXISTS _sf_audit_customer_change();
DROP FUNCTION IF EXISTS _sf_set_child_customer_meta();
DROP FUNCTION IF EXISTS _sf_set_customer_meta();

-- Remover tabelas (CASCADE remove policies e índices)
DROP TABLE IF EXISTS customer_assets    CASCADE;
DROP TABLE IF EXISTS customer_addresses CASCADE;
DROP TABLE IF EXISTS customer_contacts  CASCADE;
DROP TABLE IF EXISTS customers          CASCADE;

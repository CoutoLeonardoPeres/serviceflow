-- =============================================================================
-- Migration: 0017_customer_phone_uniqueness
-- Descricao: Impede clientes duplicados por telefone dentro do mesmo tenant
-- Depende de: 0002_customers
-- Rollback: 0017_customer_phone_uniqueness_rollback.sql
-- =============================================================================

CREATE UNIQUE INDEX uq_customers_phone_tenant
  ON customers (tenant_id, phone)
  WHERE phone IS NOT NULL;

-- =============================================================================
-- Migration: 0019_service_professional_costs
-- Descrição: custos operacionais por profissional
-- Aplicar em: development, staging, production
-- Rollback: supabase/rollbacks/0019_service_professional_costs_rollback.sql
-- =============================================================================

ALTER TABLE service_professionals
  ADD COLUMN hourly_rate_cents integer NOT NULL DEFAULT 0 CHECK (hourly_rate_cents >= 0),
  ADD COLUMN transport_cost_cents integer NOT NULL DEFAULT 0 CHECK (transport_cost_cents >= 0),
  ADD COLUMN meal_cost_cents integer NOT NULL DEFAULT 0 CHECK (meal_cost_cents >= 0),
  ADD COLUMN travel_cost_cents integer NOT NULL DEFAULT 0 CHECK (travel_cost_cents >= 0),
  ADD COLUMN lodging_cost_cents integer NOT NULL DEFAULT 0 CHECK (lodging_cost_cents >= 0),
  ADD COLUMN other_cost_cents integer NOT NULL DEFAULT 0 CHECK (other_cost_cents >= 0);

COMMENT ON COLUMN service_professionals.hourly_rate_cents IS 'Valor da hora técnica do profissional em centavos.';
COMMENT ON COLUMN service_professionals.transport_cost_cents IS 'Custo base de transporte em centavos.';
COMMENT ON COLUMN service_professionals.meal_cost_cents IS 'Custo base de refeição em centavos.';
COMMENT ON COLUMN service_professionals.travel_cost_cents IS 'Custo base de deslocamento em centavos.';
COMMENT ON COLUMN service_professionals.lodging_cost_cents IS 'Custo base de hospedagem em centavos.';
COMMENT ON COLUMN service_professionals.other_cost_cents IS 'Outros custos fixos ou recorrentes em centavos.';

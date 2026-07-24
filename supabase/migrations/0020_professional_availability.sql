-- =============================================================================
-- Migration: 0020_professional_availability
-- Descrição: disponibilidade semanal por profissional
-- Aplicar em: development, staging, production
-- Rollback: supabase/rollbacks/0020_professional_availability_rollback.sql
-- =============================================================================

ALTER TABLE service_professionals
  ADD COLUMN availability jsonb NOT NULL DEFAULT '{}'::jsonb;

COMMENT ON COLUMN service_professionals.availability IS
  'Disponibilidade semanal do profissional, incluindo manhã, tarde e noite por dia.';

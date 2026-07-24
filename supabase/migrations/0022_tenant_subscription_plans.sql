-- =============================================================================
-- Migration: 0022_tenant_subscription_plans
-- Descrição: Estrutura base de assinatura, trial e plano por tenant
-- Aplicar em: development, staging, production
-- Rollback: supabase/rollbacks/0022_tenant_subscription_plans_rollback.sql
-- =============================================================================

ALTER TABLE tenants
  ADD COLUMN IF NOT EXISTS plan_key text,
  ADD COLUMN IF NOT EXISTS billing_status text,
  ADD COLUMN IF NOT EXISTS trial_ends_at timestamptz;

UPDATE tenants
SET
  plan_key = COALESCE(plan_key, 'enterprise'),
  billing_status = COALESCE(billing_status, 'active')
WHERE plan_key IS NULL
   OR billing_status IS NULL;

ALTER TABLE tenants
  ALTER COLUMN plan_key SET DEFAULT 'starter',
  ALTER COLUMN billing_status SET DEFAULT 'trialing',
  ALTER COLUMN trial_ends_at SET DEFAULT (now() + interval '14 days');

UPDATE tenants
SET trial_ends_at = now() + interval '14 days'
WHERE trial_ends_at IS NULL
  AND billing_status = 'trialing';

ALTER TABLE tenants
  ALTER COLUMN plan_key SET NOT NULL,
  ALTER COLUMN billing_status SET NOT NULL;

ALTER TABLE tenants
  ADD CONSTRAINT tenants_plan_key_check
  CHECK (plan_key IN ('starter', 'professional', 'business', 'enterprise'));

ALTER TABLE tenants
  ADD CONSTRAINT tenants_billing_status_check
  CHECK (billing_status IN ('trialing', 'active', 'past_due', 'canceled'));

COMMENT ON COLUMN tenants.plan_key IS
  'Plano comercial atual do tenant: starter, professional, business ou enterprise.';

COMMENT ON COLUMN tenants.billing_status IS
  'Status da assinatura do tenant.';

COMMENT ON COLUMN tenants.trial_ends_at IS
  'Data final do período de trial quando billing_status = trialing.';

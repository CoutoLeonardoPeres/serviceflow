ALTER TABLE tenants
  DROP CONSTRAINT IF EXISTS tenants_billing_status_check;

ALTER TABLE tenants
  DROP CONSTRAINT IF EXISTS tenants_plan_key_check;

ALTER TABLE tenants
  ALTER COLUMN trial_ends_at DROP DEFAULT,
  ALTER COLUMN billing_status DROP DEFAULT,
  ALTER COLUMN plan_key DROP DEFAULT,
  ALTER COLUMN billing_status DROP NOT NULL,
  ALTER COLUMN plan_key DROP NOT NULL;

ALTER TABLE tenants
  DROP COLUMN IF EXISTS trial_ends_at,
  DROP COLUMN IF EXISTS billing_status,
  DROP COLUMN IF EXISTS plan_key;

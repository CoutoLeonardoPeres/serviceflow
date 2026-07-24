ALTER TABLE service_professionals
  DROP COLUMN IF EXISTS other_cost_cents,
  DROP COLUMN IF EXISTS lodging_cost_cents,
  DROP COLUMN IF EXISTS travel_cost_cents,
  DROP COLUMN IF EXISTS meal_cost_cents,
  DROP COLUMN IF EXISTS transport_cost_cents,
  DROP COLUMN IF EXISTS hourly_rate_cents;

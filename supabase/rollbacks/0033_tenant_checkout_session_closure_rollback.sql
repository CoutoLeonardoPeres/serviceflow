DROP FUNCTION IF EXISTS close_current_tenant_checkout_session(uuid, text, text, jsonb);

ALTER TABLE tenant_billing_events
  DROP CONSTRAINT IF EXISTS tenant_billing_events_event_type_check;

ALTER TABLE tenant_billing_events
  ADD CONSTRAINT tenant_billing_events_event_type_check
  CHECK (
    event_type IN (
      'trial_started',
      'plan_selected',
      'plan_changed',
      'status_changed',
      'checkout_started',
      'checkout_returned',
      'checkout_confirmed'
    )
  );

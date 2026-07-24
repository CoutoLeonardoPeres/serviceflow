DROP FUNCTION IF EXISTS register_current_tenant_checkout_return(uuid, text, jsonb);
DROP FUNCTION IF EXISTS create_current_tenant_checkout_session(text, text, text, text, jsonb);

DROP POLICY IF EXISTS "tenant_checkout_sessions_select" ON tenant_checkout_sessions;
DROP TABLE IF EXISTS tenant_checkout_sessions;

ALTER TABLE tenant_billing_events
  DROP CONSTRAINT IF EXISTS tenant_billing_events_event_type_check;

ALTER TABLE tenant_billing_events
  ADD CONSTRAINT tenant_billing_events_event_type_check
  CHECK (
    event_type IN (
      'trial_started',
      'plan_selected',
      'plan_changed',
      'status_changed'
    )
  );

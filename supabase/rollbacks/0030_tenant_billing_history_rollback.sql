DROP FUNCTION IF EXISTS update_current_tenant_billing_status(text, text, timestamptz);
DROP FUNCTION IF EXISTS log_tenant_billing_event(uuid, text, text, text, text, text, text, jsonb, uuid);

DROP TABLE IF EXISTS tenant_billing_events;

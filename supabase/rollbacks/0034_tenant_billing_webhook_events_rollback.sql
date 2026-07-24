DROP FUNCTION IF EXISTS register_current_tenant_billing_webhook_event(text, text, text, uuid, text, jsonb);

DROP POLICY IF EXISTS "tenant_billing_webhook_events_select" ON tenant_billing_webhook_events;
DROP TABLE IF EXISTS tenant_billing_webhook_events;

-- =============================================================================
-- Migration: 0034_tenant_billing_webhook_events
-- Descrição: Registro e processamento de webhooks de cobrança
-- Aplicar em: development, staging, production
-- Rollback: supabase/rollbacks/0034_tenant_billing_webhook_events_rollback.sql
-- =============================================================================

CREATE TABLE IF NOT EXISTS tenant_billing_webhook_events (
  id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  checkout_session_id uuid        REFERENCES tenant_checkout_sessions(id) ON DELETE SET NULL,
  provider            text        NOT NULL,
  provider_event_id   text,
  provider_reference  text,
  event_type          text        NOT NULL,
  processing_status   text        NOT NULL DEFAULT 'received',
  processing_note     text,
  payload             jsonb       NOT NULL DEFAULT '{}'::jsonb,
  received_at         timestamptz NOT NULL DEFAULT now(),
  processed_at        timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE tenant_billing_webhook_events IS
  'Eventos de webhook/comunicação do gateway de cobrança processados por tenant.';

ALTER TABLE tenant_billing_webhook_events
  ADD CONSTRAINT tenant_billing_webhook_events_processing_status_check
  CHECK (processing_status IN ('received', 'processed', 'ignored', 'failed'));

CREATE UNIQUE INDEX IF NOT EXISTS idx_tenant_billing_webhooks_provider_event
  ON tenant_billing_webhook_events (provider, provider_event_id)
  WHERE provider_event_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_tenant_billing_webhooks_tenant_received
  ON tenant_billing_webhook_events (tenant_id, received_at DESC);

ALTER TABLE tenant_billing_webhook_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tenant_billing_webhook_events_select" ON tenant_billing_webhook_events
  FOR SELECT TO authenticated
  USING (tenant_id = current_tenant_id());

CREATE OR REPLACE FUNCTION register_current_tenant_billing_webhook_event(
  p_provider text,
  p_event_type text,
  p_provider_event_id text DEFAULT NULL,
  p_checkout_session_id uuid DEFAULT NULL,
  p_provider_reference text DEFAULT NULL,
  p_payload jsonb DEFAULT '{}'::jsonb
)
RETURNS tenant_billing_webhook_events
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid := current_tenant_id();
  v_user_id uuid := auth.uid();
  v_event tenant_billing_webhook_events%ROWTYPE;
  v_existing tenant_billing_webhook_events%ROWTYPE;
  v_session tenant_checkout_sessions%ROWTYPE;
  v_note text;
BEGIN
  IF v_tenant_id IS NULL OR v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuário sem tenant ativo.'
      USING ERRCODE = '42501';
  END IF;

  IF NOT (
    has_permission('tenant_settings.update')
    OR is_platform_admin()
  ) THEN
    RAISE EXCEPTION 'Usuário sem permissão para registrar webhook.'
      USING ERRCODE = '42501';
  END IF;

  IF COALESCE(trim(p_provider), '') = '' THEN
    RAISE EXCEPTION 'Provider do webhook é obrigatório.'
      USING ERRCODE = '22023';
  END IF;

  IF COALESCE(trim(p_event_type), '') = '' THEN
    RAISE EXCEPTION 'Tipo do webhook é obrigatório.'
      USING ERRCODE = '22023';
  END IF;

  IF p_provider_event_id IS NOT NULL THEN
    SELECT *
      INTO v_existing
    FROM tenant_billing_webhook_events
    WHERE provider = trim(p_provider)
      AND provider_event_id = trim(p_provider_event_id)
    LIMIT 1;

    IF FOUND THEN
      RETURN v_existing;
    END IF;
  END IF;

  IF p_checkout_session_id IS NOT NULL THEN
    SELECT *
      INTO v_session
    FROM tenant_checkout_sessions
    WHERE id = p_checkout_session_id
      AND tenant_id = v_tenant_id
    LIMIT 1;
  ELSIF COALESCE(trim(COALESCE(p_provider_reference, '')), '') <> '' THEN
    SELECT *
      INTO v_session
    FROM tenant_checkout_sessions
    WHERE tenant_id = v_tenant_id
      AND provider_reference = trim(p_provider_reference)
    ORDER BY created_at DESC
    LIMIT 1;
  END IF;

  INSERT INTO tenant_billing_webhook_events (
    tenant_id,
    checkout_session_id,
    provider,
    provider_event_id,
    provider_reference,
    event_type,
    processing_status,
    payload
  )
  VALUES (
    v_tenant_id,
    v_session.id,
    trim(p_provider),
    NULLIF(trim(COALESCE(p_provider_event_id, '')), ''),
    NULLIF(trim(COALESCE(p_provider_reference, '')), ''),
    trim(p_event_type),
    'received',
    COALESCE(p_payload, '{}'::jsonb)
  )
  RETURNING * INTO v_event;

  IF v_session.id IS NULL THEN
    UPDATE tenant_billing_webhook_events
    SET
      processing_status = 'failed',
      processing_note = 'Nenhuma sessão de checkout relacionada foi encontrada.',
      processed_at = now()
    WHERE id = v_event.id
    RETURNING * INTO v_event;

    RETURN v_event;
  END IF;

  IF trim(p_event_type) IN (
    'payment_succeeded',
    'checkout.confirmed',
    'invoice.paid',
    'subscription.activated'
  ) THEN
    PERFORM confirm_current_tenant_checkout_session(
      v_session.id,
      p_note => 'Assinatura ativada por webhook.',
      p_provider_reference => p_provider_reference,
      p_metadata => jsonb_build_object(
        'provider', trim(p_provider),
        'provider_event_id', NULLIF(trim(COALESCE(p_provider_event_id, '')), ''),
        'webhook_event_id', v_event.id
      )
    );
    v_note := 'Webhook processado e assinatura ativada.';
    UPDATE tenant_billing_webhook_events
    SET
      processing_status = 'processed',
      processing_note = v_note,
      processed_at = now()
    WHERE id = v_event.id
    RETURNING * INTO v_event;
    RETURN v_event;
  END IF;

  IF trim(p_event_type) IN (
    'payment_canceled',
    'checkout.canceled',
    'subscription.canceled'
  ) THEN
    PERFORM close_current_tenant_checkout_session(
      v_session.id,
      'canceled',
      'Webhook indicou cancelamento do checkout.',
      jsonb_build_object(
        'provider', trim(p_provider),
        'provider_event_id', NULLIF(trim(COALESCE(p_provider_event_id, '')), ''),
        'webhook_event_id', v_event.id
      )
    );
    v_note := 'Webhook processado e checkout cancelado.';
    UPDATE tenant_billing_webhook_events
    SET
      processing_status = 'processed',
      processing_note = v_note,
      processed_at = now()
    WHERE id = v_event.id
    RETURNING * INTO v_event;
    RETURN v_event;
  END IF;

  IF trim(p_event_type) IN (
    'payment_expired',
    'checkout.expired',
    'invoice.expired'
  ) THEN
    PERFORM close_current_tenant_checkout_session(
      v_session.id,
      'expired',
      'Webhook indicou expiração do checkout.',
      jsonb_build_object(
        'provider', trim(p_provider),
        'provider_event_id', NULLIF(trim(COALESCE(p_provider_event_id, '')), ''),
        'webhook_event_id', v_event.id
      )
    );
    v_note := 'Webhook processado e checkout expirado.';
    UPDATE tenant_billing_webhook_events
    SET
      processing_status = 'processed',
      processing_note = v_note,
      processed_at = now()
    WHERE id = v_event.id
    RETURNING * INTO v_event;
    RETURN v_event;
  END IF;

  UPDATE tenant_billing_webhook_events
  SET
    processing_status = 'ignored',
    processing_note = 'Evento recebido sem ação automatizada configurada.',
    processed_at = now()
  WHERE id = v_event.id
  RETURNING * INTO v_event;

  RETURN v_event;
END;
$$;

GRANT EXECUTE ON FUNCTION register_current_tenant_billing_webhook_event(text, text, text, uuid, text, jsonb) TO authenticated;

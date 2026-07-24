-- =============================================================================
-- Migration: 0033_tenant_checkout_session_closure
-- Descrição: Cancelamento e expiração de sessões de checkout
-- Aplicar em: development, staging, production
-- Rollback: supabase/rollbacks/0033_tenant_checkout_session_closure_rollback.sql
-- =============================================================================

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
      'checkout_confirmed',
      'checkout_canceled',
      'checkout_expired'
    )
  );

CREATE OR REPLACE FUNCTION close_current_tenant_checkout_session(
  p_checkout_session_id uuid,
  p_target_status text,
  p_note text DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS tenant_checkout_sessions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid := current_tenant_id();
  v_user_id uuid := auth.uid();
  v_session tenant_checkout_sessions%ROWTYPE;
  v_current tenants%ROWTYPE;
  v_event_type text;
BEGIN
  IF v_tenant_id IS NULL OR v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuário sem tenant ativo.'
      USING ERRCODE = '42501';
  END IF;

  IF NOT (
    has_permission('tenant_settings.update')
    OR is_platform_admin()
  ) THEN
    RAISE EXCEPTION 'Usuário sem permissão para encerrar o checkout.'
      USING ERRCODE = '42501';
  END IF;

  IF p_target_status NOT IN ('canceled', 'expired') THEN
    RAISE EXCEPTION 'Status de encerramento inválido: %', p_target_status
      USING ERRCODE = '22023';
  END IF;

  SELECT *
    INTO v_session
  FROM tenant_checkout_sessions
  WHERE id = p_checkout_session_id
    AND tenant_id = v_tenant_id
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sessão de checkout não encontrada.'
      USING ERRCODE = 'P0001';
  END IF;

  IF v_session.status = 'confirmed' THEN
    RAISE EXCEPTION 'Não é possível encerrar uma sessão já confirmada.'
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE tenant_checkout_sessions
  SET
    status = p_target_status,
    canceled_at = CASE
      WHEN p_target_status = 'canceled' THEN COALESCE(canceled_at, now())
      ELSE canceled_at
    END,
    expires_at = CASE
      WHEN p_target_status = 'expired' THEN COALESCE(expires_at, now())
      ELSE expires_at
    END,
    metadata = tenant_checkout_sessions.metadata || COALESCE(p_metadata, '{}'::jsonb),
    updated_at = now()
  WHERE id = p_checkout_session_id
  RETURNING * INTO v_session;

  SELECT *
    INTO v_current
  FROM tenants
  WHERE id = v_tenant_id;

  v_event_type := CASE
    WHEN p_target_status = 'canceled' THEN 'checkout_canceled'
    ELSE 'checkout_expired'
  END;

  PERFORM log_audit(
    v_tenant_id,
    'tenant.checkout.closed',
    'tenant_checkout_sessions',
    v_session.id::text,
    NULL,
    jsonb_build_object(
      'target_status', p_target_status,
      'note', p_note
    )
  );

  PERFORM log_tenant_billing_event(
    p_tenant_id => v_tenant_id,
    p_event_type => v_event_type,
    p_plan_key => v_session.plan_key,
    p_previous_plan_key => v_current.plan_key,
    p_billing_status => v_current.billing_status,
    p_previous_billing_status => v_current.billing_status,
    p_note => COALESCE(
      p_note,
      CASE
        WHEN p_target_status = 'canceled' THEN 'Checkout cancelado manualmente.'
        ELSE 'Checkout expirado sem confirmação.'
      END
    ),
    p_metadata => jsonb_build_object(
      'source', v_session.source,
      'checkout_session_id', v_session.id,
      'target_status', p_target_status
    ) || COALESCE(p_metadata, '{}'::jsonb),
    p_actor_user_id => v_user_id
  );

  RETURN v_session;
END;
$$;

GRANT EXECUTE ON FUNCTION close_current_tenant_checkout_session(uuid, text, text, jsonb) TO authenticated;

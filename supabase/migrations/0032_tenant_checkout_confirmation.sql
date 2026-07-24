-- =============================================================================
-- Migration: 0032_tenant_checkout_confirmation
-- Descrição: Confirmação de checkout e ativação comercial do tenant
-- Aplicar em: development, staging, production
-- Rollback: supabase/rollbacks/0032_tenant_checkout_confirmation_rollback.sql
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
      'checkout_confirmed'
    )
  );

CREATE OR REPLACE FUNCTION confirm_current_tenant_checkout_session(
  p_checkout_session_id uuid,
  p_note text DEFAULT NULL,
  p_provider_reference text DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb
)
RETURNS tenants
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid := current_tenant_id();
  v_user_id uuid := auth.uid();
  v_session tenant_checkout_sessions%ROWTYPE;
  v_current tenants%ROWTYPE;
  v_updated tenants%ROWTYPE;
BEGIN
  IF v_tenant_id IS NULL OR v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuário sem tenant ativo.'
      USING ERRCODE = '42501';
  END IF;

  IF NOT (
    has_permission('tenant_settings.update')
    OR is_platform_admin()
  ) THEN
    RAISE EXCEPTION 'Usuário sem permissão para confirmar o checkout.'
      USING ERRCODE = '42501';
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

  SELECT *
    INTO v_current
  FROM tenants
  WHERE id = v_tenant_id;

  UPDATE tenant_checkout_sessions
  SET
    status = 'confirmed',
    provider_reference = COALESCE(
      NULLIF(trim(COALESCE(p_provider_reference, '')), ''),
      provider_reference
    ),
    returned_at = COALESCE(returned_at, now()),
    confirmed_at = COALESCE(confirmed_at, now()),
    metadata = tenant_checkout_sessions.metadata || COALESCE(p_metadata, '{}'::jsonb),
    updated_at = now()
  WHERE id = p_checkout_session_id
  RETURNING * INTO v_session;

  UPDATE tenants
  SET
    plan_key = v_session.plan_key,
    billing_status = 'active',
    trial_ends_at = CASE
      WHEN billing_status = 'trialing' THEN trial_ends_at
      ELSE NULL
    END,
    plan_selected_at = COALESCE(plan_selected_at, now()),
    updated_at = now()
  WHERE id = v_tenant_id
  RETURNING * INTO v_updated;

  PERFORM log_audit(
    v_tenant_id,
    'tenant.checkout.confirmed',
    'tenant_checkout_sessions',
    v_session.id::text,
    NULL,
    jsonb_build_object(
      'plan_key', v_session.plan_key,
      'provider_reference', p_provider_reference,
      'note', p_note
    )
  );

  IF v_current.plan_key IS DISTINCT FROM v_updated.plan_key THEN
    PERFORM log_tenant_billing_event(
      p_tenant_id => v_tenant_id,
      p_event_type => 'plan_changed',
      p_plan_key => v_updated.plan_key,
      p_previous_plan_key => v_current.plan_key,
      p_billing_status => v_updated.billing_status,
      p_previous_billing_status => v_current.billing_status,
      p_note => COALESCE(p_note, 'Plano ativado após confirmação do checkout.'),
      p_metadata => jsonb_build_object(
        'source', v_session.source,
        'checkout_session_id', v_session.id
      ),
      p_actor_user_id => v_user_id
    );
  END IF;

  IF v_current.billing_status IS DISTINCT FROM v_updated.billing_status THEN
    PERFORM log_tenant_billing_event(
      p_tenant_id => v_tenant_id,
      p_event_type => 'status_changed',
      p_plan_key => v_updated.plan_key,
      p_previous_plan_key => v_current.plan_key,
      p_billing_status => v_updated.billing_status,
      p_previous_billing_status => v_current.billing_status,
      p_note => COALESCE(p_note, 'Assinatura ativada após confirmação do checkout.'),
      p_metadata => jsonb_build_object(
        'source', v_session.source,
        'checkout_session_id', v_session.id
      ),
      p_actor_user_id => v_user_id
    );
  END IF;

  PERFORM log_tenant_billing_event(
    p_tenant_id => v_tenant_id,
    p_event_type => 'checkout_confirmed',
    p_plan_key => v_updated.plan_key,
    p_previous_plan_key => v_current.plan_key,
    p_billing_status => v_updated.billing_status,
    p_previous_billing_status => v_current.billing_status,
    p_note => COALESCE(p_note, 'Pagamento/checkout confirmado.'),
    p_metadata => jsonb_build_object(
      'source', v_session.source,
      'checkout_session_id', v_session.id,
      'provider_reference', NULLIF(trim(COALESCE(p_provider_reference, '')), '')
    ) || COALESCE(p_metadata, '{}'::jsonb),
    p_actor_user_id => v_user_id
  );

  RETURN v_updated;
END;
$$;

GRANT EXECUTE ON FUNCTION confirm_current_tenant_checkout_session(uuid, text, text, jsonb) TO authenticated;

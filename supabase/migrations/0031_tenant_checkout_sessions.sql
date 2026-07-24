-- =============================================================================
-- Migration: 0031_tenant_checkout_sessions
-- Descrição: Sessões de checkout rastreáveis para onboarding e cobrança
-- Aplicar em: development, staging, production
-- Rollback: supabase/rollbacks/0031_tenant_checkout_sessions_rollback.sql
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
      'checkout_returned'
    )
  );

CREATE TABLE IF NOT EXISTS tenant_checkout_sessions (
  id                  uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id           uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  plan_key            text        NOT NULL,
  source              text        NOT NULL,
  status              text        NOT NULL DEFAULT 'pending',
  provider            text,
  provider_reference  text,
  return_url          text,
  metadata            jsonb       NOT NULL DEFAULT '{}'::jsonb,
  actor_user_id       uuid,
  returned_at         timestamptz,
  confirmed_at        timestamptz,
  canceled_at         timestamptz,
  expires_at          timestamptz,
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE tenant_checkout_sessions IS
  'Tentativas de checkout da assinatura para rastrear abertura, retorno e confirmação.';

ALTER TABLE tenant_checkout_sessions
  ADD CONSTRAINT tenant_checkout_sessions_plan_key_check
  CHECK (plan_key IN ('starter', 'professional', 'business', 'enterprise'));

ALTER TABLE tenant_checkout_sessions
  ADD CONSTRAINT tenant_checkout_sessions_status_check
  CHECK (status IN ('pending', 'returned', 'confirmed', 'canceled', 'expired'));

CREATE INDEX IF NOT EXISTS idx_tenant_checkout_sessions_tenant_created
  ON tenant_checkout_sessions (tenant_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_tenant_checkout_sessions_tenant_status
  ON tenant_checkout_sessions (tenant_id, status);

ALTER TABLE tenant_checkout_sessions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tenant_checkout_sessions_select" ON tenant_checkout_sessions
  FOR SELECT TO authenticated
  USING (tenant_id = current_tenant_id());

CREATE OR REPLACE FUNCTION create_current_tenant_checkout_session(
  p_plan_key text,
  p_source text,
  p_return_url text DEFAULT NULL,
  p_provider text DEFAULT NULL,
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
  v_row tenant_checkout_sessions%ROWTYPE;
  v_current tenants%ROWTYPE;
  v_user_limit integer;
  v_unit_limit integer;
  v_active_users integer;
  v_active_units integer;
BEGIN
  IF v_tenant_id IS NULL OR v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuário sem tenant ativo.'
      USING ERRCODE = '42501';
  END IF;

  IF NOT (
    has_permission('tenant_settings.update')
    OR is_platform_admin()
  ) THEN
    RAISE EXCEPTION 'Usuário sem permissão para iniciar o checkout.'
      USING ERRCODE = '42501';
  END IF;

  IF p_plan_key NOT IN ('starter', 'professional', 'business', 'enterprise') THEN
    RAISE EXCEPTION 'Plano inválido: %', p_plan_key
      USING ERRCODE = '22023';
  END IF;

  IF COALESCE(trim(p_source), '') = '' THEN
    RAISE EXCEPTION 'Origem do checkout é obrigatória.'
      USING ERRCODE = '22023';
  END IF;

  SELECT *
    INTO v_current
  FROM tenants
  WHERE id = v_tenant_id;

  v_user_limit := plan_user_limit(p_plan_key);
  v_unit_limit := plan_unit_limit(p_plan_key);

  SELECT count(*)
    INTO v_active_users
  FROM tenant_memberships
  WHERE tenant_id = v_tenant_id
    AND status = 'active';

  IF v_active_users > v_user_limit THEN
    RAISE EXCEPTION
      'Não é possível iniciar o checkout de %: há % usuário(s) ativos e o limite do plano é %.',
      p_plan_key,
      v_active_users,
      v_user_limit
      USING ERRCODE = 'P0001';
  END IF;

  SELECT count(*)
    INTO v_active_units
  FROM tenant_units
  WHERE tenant_id = v_tenant_id
    AND is_active = true;

  IF v_active_units > v_unit_limit THEN
    RAISE EXCEPTION
      'Não é possível iniciar o checkout de %: há % unidade(s) ativas e o limite do plano é %.',
      p_plan_key,
      v_active_units,
      v_unit_limit
      USING ERRCODE = 'P0001';
  END IF;

  INSERT INTO tenant_checkout_sessions (
    tenant_id,
    plan_key,
    source,
    status,
    provider,
    return_url,
    metadata,
    actor_user_id,
    expires_at
  )
  VALUES (
    v_tenant_id,
    p_plan_key,
    trim(p_source),
    'pending',
    NULLIF(trim(COALESCE(p_provider, '')), ''),
    NULLIF(trim(COALESCE(p_return_url, '')), ''),
    COALESCE(p_metadata, '{}'::jsonb),
    v_user_id,
    now() + interval '1 day'
  )
  RETURNING * INTO v_row;

  PERFORM log_audit(
    v_tenant_id,
    'tenant.checkout.started',
    'tenant_checkout_sessions',
    v_row.id::text,
    NULL,
    jsonb_build_object(
      'plan_key', p_plan_key,
      'source', trim(p_source),
      'return_url', p_return_url
    )
  );

  PERFORM log_tenant_billing_event(
    p_tenant_id => v_tenant_id,
    p_event_type => 'checkout_started',
    p_plan_key => p_plan_key,
    p_previous_plan_key => v_current.plan_key,
    p_billing_status => v_current.billing_status,
    p_previous_billing_status => v_current.billing_status,
    p_note => 'Checkout iniciado para assinatura.',
    p_metadata => jsonb_build_object(
      'source', trim(p_source),
      'checkout_session_id', v_row.id,
      'provider', NULLIF(trim(COALESCE(p_provider, '')), '')
    ),
    p_actor_user_id => v_user_id
  );

  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION register_current_tenant_checkout_return(
  p_checkout_session_id uuid,
  p_provider_reference text DEFAULT NULL,
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
  v_row tenant_checkout_sessions%ROWTYPE;
  v_current tenants%ROWTYPE;
BEGIN
  IF v_tenant_id IS NULL OR v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuário sem tenant ativo.'
      USING ERRCODE = '42501';
  END IF;

  SELECT *
    INTO v_row
  FROM tenant_checkout_sessions
  WHERE id = p_checkout_session_id
    AND tenant_id = v_tenant_id
  LIMIT 1;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Sessão de checkout não encontrada.'
      USING ERRCODE = 'P0001';
  END IF;

  IF v_row.status IN ('confirmed', 'canceled', 'expired') THEN
    RETURN v_row;
  END IF;

  UPDATE tenant_checkout_sessions
  SET
    status = 'returned',
    provider_reference = COALESCE(
      NULLIF(trim(COALESCE(p_provider_reference, '')), ''),
      provider_reference
    ),
    returned_at = COALESCE(returned_at, now()),
    metadata = tenant_checkout_sessions.metadata || COALESCE(p_metadata, '{}'::jsonb),
    updated_at = now()
  WHERE id = p_checkout_session_id
  RETURNING * INTO v_row;

  SELECT *
    INTO v_current
  FROM tenants
  WHERE id = v_tenant_id;

  PERFORM log_audit(
    v_tenant_id,
    'tenant.checkout.returned',
    'tenant_checkout_sessions',
    v_row.id::text,
    NULL,
    jsonb_build_object(
      'provider_reference', p_provider_reference,
      'metadata', COALESCE(p_metadata, '{}'::jsonb)
    )
  );

  PERFORM log_tenant_billing_event(
    p_tenant_id => v_tenant_id,
    p_event_type => 'checkout_returned',
    p_plan_key => v_row.plan_key,
    p_previous_plan_key => v_current.plan_key,
    p_billing_status => v_current.billing_status,
    p_previous_billing_status => v_current.billing_status,
    p_note => 'Retorno do checkout recebido e aguardando confirmação do pagamento.',
    p_metadata => jsonb_build_object(
      'source', v_row.source,
      'checkout_session_id', v_row.id,
      'provider_reference', NULLIF(trim(COALESCE(p_provider_reference, '')), '')
    ) || COALESCE(p_metadata, '{}'::jsonb),
    p_actor_user_id => v_user_id
  );

  RETURN v_row;
END;
$$;

GRANT EXECUTE ON FUNCTION create_current_tenant_checkout_session(text, text, text, text, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION register_current_tenant_checkout_return(uuid, text, jsonb) TO authenticated;

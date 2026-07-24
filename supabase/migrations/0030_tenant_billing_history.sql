-- =============================================================================
-- Migration: 0030_tenant_billing_history
-- Descrição: Histórico comercial e transições de assinatura do tenant
-- Aplicar em: development, staging, production
-- Rollback: supabase/rollbacks/0030_tenant_billing_history_rollback.sql
-- =============================================================================

CREATE TABLE IF NOT EXISTS tenant_billing_events (
  id                      uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id               uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  event_type              text        NOT NULL,
  plan_key                text,
  previous_plan_key       text,
  billing_status          text,
  previous_billing_status text,
  note                    text,
  metadata                jsonb       NOT NULL DEFAULT '{}'::jsonb,
  actor_user_id           uuid,
  occurred_at             timestamptz NOT NULL DEFAULT now(),
  created_at              timestamptz NOT NULL DEFAULT now()
);

COMMENT ON TABLE tenant_billing_events IS
  'Linha do tempo comercial do tenant: escolha de plano, troca, trial e status de assinatura.';

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

ALTER TABLE tenant_billing_events
  ADD CONSTRAINT tenant_billing_events_plan_key_check
  CHECK (plan_key IS NULL OR plan_key IN ('starter', 'professional', 'business', 'enterprise'));

ALTER TABLE tenant_billing_events
  ADD CONSTRAINT tenant_billing_events_previous_plan_key_check
  CHECK (previous_plan_key IS NULL OR previous_plan_key IN ('starter', 'professional', 'business', 'enterprise'));

ALTER TABLE tenant_billing_events
  ADD CONSTRAINT tenant_billing_events_status_check
  CHECK (billing_status IS NULL OR billing_status IN ('trialing', 'active', 'past_due', 'canceled'));

ALTER TABLE tenant_billing_events
  ADD CONSTRAINT tenant_billing_events_previous_status_check
  CHECK (previous_billing_status IS NULL OR previous_billing_status IN ('trialing', 'active', 'past_due', 'canceled'));

CREATE INDEX IF NOT EXISTS idx_tenant_billing_events_tenant_occurred
  ON tenant_billing_events (tenant_id, occurred_at DESC);

ALTER TABLE tenant_billing_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "tenant_billing_events_select" ON tenant_billing_events
  FOR SELECT TO authenticated
  USING (tenant_id = current_tenant_id());

CREATE OR REPLACE FUNCTION log_tenant_billing_event(
  p_tenant_id uuid,
  p_event_type text,
  p_plan_key text DEFAULT NULL,
  p_previous_plan_key text DEFAULT NULL,
  p_billing_status text DEFAULT NULL,
  p_previous_billing_status text DEFAULT NULL,
  p_note text DEFAULT NULL,
  p_metadata jsonb DEFAULT '{}'::jsonb,
  p_actor_user_id uuid DEFAULT auth.uid()
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO tenant_billing_events (
    tenant_id,
    event_type,
    plan_key,
    previous_plan_key,
    billing_status,
    previous_billing_status,
    note,
    metadata,
    actor_user_id
  )
  VALUES (
    p_tenant_id,
    p_event_type,
    p_plan_key,
    p_previous_plan_key,
    p_billing_status,
    p_previous_billing_status,
    p_note,
    COALESCE(p_metadata, '{}'::jsonb),
    p_actor_user_id
  );
END;
$$;

CREATE OR REPLACE FUNCTION update_current_tenant_plan(
  p_plan_key text
) RETURNS tenants
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_row tenants%ROWTYPE;
  v_current tenants%ROWTYPE;
  v_user_limit integer;
  v_unit_limit integer;
  v_active_users integer;
  v_active_units integer;
BEGIN
  v_tenant_id := current_tenant_id();

  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'Nenhum tenant ativo encontrado.'
      USING ERRCODE = '42501';
  END IF;

  IF NOT (
    has_permission('tenant_settings.update')
    OR is_platform_admin()
  ) THEN
    RAISE EXCEPTION 'Usuário sem permissão para alterar o plano.'
      USING ERRCODE = '42501';
  END IF;

  IF p_plan_key NOT IN ('starter', 'professional', 'business', 'enterprise') THEN
    RAISE EXCEPTION 'Plano inválido: %', p_plan_key
      USING ERRCODE = '22023';
  END IF;

  SELECT *
    INTO v_current
  FROM tenants
  WHERE id = v_tenant_id;

  v_user_limit := plan_user_limit(p_plan_key);
  v_unit_limit := plan_unit_limit(p_plan_key);

  SELECT COUNT(*)
    INTO v_active_users
  FROM tenant_memberships tm
  WHERE tm.tenant_id = v_tenant_id
    AND tm.status = 'active';

  IF v_active_users > v_user_limit THEN
    RAISE EXCEPTION
      'Não é possível mudar para %: há % usuário(s) ativos e o limite do plano é %.',
      p_plan_key,
      v_active_users,
      v_user_limit
      USING ERRCODE = 'P0001';
  END IF;

  SELECT COUNT(*)
    INTO v_active_units
  FROM tenant_units tu
  WHERE tu.tenant_id = v_tenant_id
    AND tu.is_active = true;

  IF v_active_units > v_unit_limit THEN
    RAISE EXCEPTION
      'Não é possível mudar para %: há % unidade(s) ativas e o limite do plano é %.',
      p_plan_key,
      v_active_units,
      v_unit_limit
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE tenants
  SET
    plan_key = p_plan_key,
    billing_status = CASE
      WHEN billing_status IS NULL THEN 'active'
      ELSE billing_status
    END,
    plan_selected_at = COALESCE(plan_selected_at, now()),
    updated_at = now()
  WHERE id = v_tenant_id
  RETURNING * INTO v_row;

  PERFORM log_audit(
    v_tenant_id,
    'tenant.plan.updated',
    'tenants',
    v_tenant_id::text,
    NULL,
    jsonb_build_object('plan_key', p_plan_key)
  );

  PERFORM log_tenant_billing_event(
    p_tenant_id => v_tenant_id,
    p_event_type => 'plan_changed',
    p_plan_key => v_row.plan_key,
    p_previous_plan_key => v_current.plan_key,
    p_billing_status => v_row.billing_status,
    p_previous_billing_status => v_current.billing_status,
    p_note => 'Plano alterado manualmente em Configurações.',
    p_metadata => jsonb_build_object('source', 'settings')
  );

  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION complete_current_tenant_plan_selection(
  p_plan_key text DEFAULT NULL
)
RETURNS tenants
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid := auth_tenant_id();
  v_user_id uuid := auth.uid();
  v_role_key text;
  v_target_plan text;
  v_active_users integer;
  v_active_units integer;
  v_user_limit integer;
  v_unit_limit integer;
  v_current tenants%ROWTYPE;
  v_updated tenants%ROWTYPE;
BEGIN
  IF v_tenant_id IS NULL OR v_user_id IS NULL THEN
    RAISE EXCEPTION 'Usuário sem tenant ativo.'
      USING ERRCODE = '42501';
  END IF;

  SELECT r.key
    INTO v_role_key
  FROM tenant_memberships tm
  JOIN roles r ON r.id = tm.role_id
  WHERE tm.tenant_id = v_tenant_id
    AND tm.user_id = v_user_id
    AND tm.status = 'active'
  LIMIT 1;

  IF v_role_key NOT IN ('tenant_owner', 'tenant_admin', 'platform_admin') THEN
    RAISE EXCEPTION 'Usuário sem permissão para confirmar o plano.'
      USING ERRCODE = '42501';
  END IF;

  SELECT *
    INTO v_current
  FROM tenants
  WHERE id = v_tenant_id;

  v_target_plan := COALESCE(p_plan_key, v_current.plan_key);

  IF v_target_plan NOT IN ('starter', 'professional', 'business', 'enterprise') THEN
    RAISE EXCEPTION 'Plano inválido: %', v_target_plan
      USING ERRCODE = '22023';
  END IF;

  v_user_limit := plan_user_limit(v_target_plan);
  v_unit_limit := plan_unit_limit(v_target_plan);

  SELECT count(*)
    INTO v_active_users
  FROM tenant_memberships
  WHERE tenant_id = v_tenant_id
    AND status = 'active';

  IF v_active_users > v_user_limit THEN
    RAISE EXCEPTION
      'Não é possível confirmar %: há % usuário(s) ativos e o limite do plano é %.',
      v_target_plan,
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
      'Não é possível confirmar %: há % unidade(s) ativas e o limite do plano é %.',
      v_target_plan,
      v_active_units,
      v_unit_limit
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE tenants
  SET
    plan_key = v_target_plan,
    plan_selected_at = COALESCE(plan_selected_at, now()),
    updated_at = now()
  WHERE id = v_tenant_id
  RETURNING * INTO v_updated;

  INSERT INTO audit_logs (
    tenant_id,
    actor_user_id,
    action,
    entity_table,
    entity_id,
    after_data
  )
  VALUES (
    v_tenant_id,
    v_user_id,
    'tenant.plan.selected',
    'tenants',
    v_tenant_id,
    jsonb_build_object('plan_key', v_target_plan)
  );

  PERFORM log_tenant_billing_event(
    p_tenant_id => v_tenant_id,
    p_event_type => 'plan_selected',
    p_plan_key => v_updated.plan_key,
    p_previous_plan_key => v_current.plan_key,
    p_billing_status => v_updated.billing_status,
    p_previous_billing_status => v_current.billing_status,
    p_note => 'Plano inicial confirmado no onboarding comercial.',
    p_metadata => jsonb_build_object('source', 'plan_onboarding'),
    p_actor_user_id => v_user_id
  );

  RETURN v_updated;
END;
$$;

CREATE OR REPLACE FUNCTION update_current_tenant_billing_status(
  p_billing_status text,
  p_note text DEFAULT NULL,
  p_trial_ends_at timestamptz DEFAULT NULL
)
RETURNS tenants
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid := current_tenant_id();
  v_current tenants%ROWTYPE;
  v_updated tenants%ROWTYPE;
BEGIN
  IF v_tenant_id IS NULL THEN
    RAISE EXCEPTION 'Nenhum tenant ativo encontrado.'
      USING ERRCODE = '42501';
  END IF;

  IF NOT (
    has_permission('tenant_settings.update')
    OR is_platform_admin()
  ) THEN
    RAISE EXCEPTION 'Usuário sem permissão para alterar o status da assinatura.'
      USING ERRCODE = '42501';
  END IF;

  IF p_billing_status NOT IN ('trialing', 'active', 'past_due', 'canceled') THEN
    RAISE EXCEPTION 'Status inválido: %', p_billing_status
      USING ERRCODE = '22023';
  END IF;

  SELECT *
    INTO v_current
  FROM tenants
  WHERE id = v_tenant_id;

  UPDATE tenants
  SET
    billing_status = p_billing_status,
    trial_ends_at = CASE
      WHEN p_billing_status = 'trialing'
        THEN COALESCE(p_trial_ends_at, trial_ends_at, now() + interval '14 days')
      ELSE trial_ends_at
    END,
    plan_selected_at = COALESCE(plan_selected_at, now()),
    updated_at = now()
  WHERE id = v_tenant_id
  RETURNING * INTO v_updated;

  PERFORM log_audit(
    v_tenant_id,
    'tenant.billing_status.updated',
    'tenants',
    v_tenant_id::text,
    NULL,
    jsonb_build_object(
      'billing_status', p_billing_status,
      'note', p_note
    )
  );

  PERFORM log_tenant_billing_event(
    p_tenant_id => v_tenant_id,
    p_event_type => 'status_changed',
    p_plan_key => v_updated.plan_key,
    p_previous_plan_key => v_current.plan_key,
    p_billing_status => v_updated.billing_status,
    p_previous_billing_status => v_current.billing_status,
    p_note => p_note,
    p_metadata => jsonb_build_object(
      'source', 'settings',
      'trial_ends_at', v_updated.trial_ends_at
    )
  );

  RETURN v_updated;
END;
$$;

GRANT EXECUTE ON FUNCTION log_tenant_billing_event(uuid, text, text, text, text, text, text, jsonb, uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION update_current_tenant_billing_status(text, text, timestamptz) TO authenticated;

INSERT INTO tenant_billing_events (
  tenant_id,
  event_type,
  plan_key,
  billing_status,
  note,
  metadata,
  occurred_at,
  created_at
)
SELECT
  t.id,
  'trial_started',
  t.plan_key,
  t.billing_status,
  'Estado comercial inicial carregado na linha do tempo.',
  jsonb_build_object('backfill', true),
  COALESCE(t.plan_selected_at, t.created_at, now()),
  now()
FROM tenants t
WHERE NOT EXISTS (
  SELECT 1
  FROM tenant_billing_events e
  WHERE e.tenant_id = t.id
);

-- =============================================================================
-- Migration: 0026_member_management
-- Descrição: RPCs para convite e gestão de status de membros
-- Aplicar em: development, staging, production
-- Rollback: supabase/rollbacks/0026_member_management_rollback.sql
-- =============================================================================

CREATE OR REPLACE FUNCTION create_tenant_invitation(
  p_email text,
  p_role_key text,
  p_expires_in_days integer DEFAULT 7
) RETURNS TABLE (
  invitation_id uuid,
  invitation_token text,
  expires_at timestamptz
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_role_id uuid;
  v_token text;
  v_hash text;
  v_invitation_id uuid;
  v_expires_at timestamptz;
BEGIN
  v_tenant_id := current_tenant_id();

  IF v_tenant_id IS NULL OR NOT has_permission('members.manage') THEN
    RAISE EXCEPTION 'Usuário sem permissão para convidar membros.'
      USING ERRCODE = '42501';
  END IF;

  IF p_email IS NULL OR btrim(p_email) = '' THEN
    RAISE EXCEPTION 'E-mail obrigatório.'
      USING ERRCODE = '22023';
  END IF;

  SELECT r.id INTO v_role_id
  FROM roles r
  WHERE r.key = p_role_key
    AND r.key <> 'platform_admin';

  IF v_role_id IS NULL THEN
    RAISE EXCEPTION 'Papel inválido: %', p_role_key
      USING ERRCODE = '22023';
  END IF;

  UPDATE user_invitations
  SET revoked_at = now()
  WHERE tenant_id = v_tenant_id
    AND lower(email) = lower(btrim(p_email))
    AND accepted_at IS NULL
    AND revoked_at IS NULL;

  v_token := encode(gen_random_bytes(24), 'hex');
  v_hash := encode(digest(v_token, 'sha256'), 'hex');
  v_expires_at := now() + make_interval(days => GREATEST(COALESCE(p_expires_in_days, 7), 1));

  INSERT INTO user_invitations (
    tenant_id, email, role_id, token_hash, expires_at, created_by
  )
  VALUES (
    v_tenant_id, lower(btrim(p_email)), v_role_id, v_hash, v_expires_at, auth.uid()
  )
  RETURNING id INTO v_invitation_id;

  PERFORM log_audit(
    v_tenant_id,
    'member.invited',
    'user_invitations',
    v_invitation_id::text,
    NULL,
    jsonb_build_object('email', lower(btrim(p_email)), 'role_key', p_role_key)
  );

  RETURN QUERY
  SELECT v_invitation_id, v_token, v_expires_at;
END;
$$;

CREATE OR REPLACE FUNCTION list_tenant_members()
RETURNS TABLE (
  id uuid,
  user_id uuid,
  status text,
  full_name text,
  email text,
  role_key text,
  role_name text
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT
    tm.id,
    tm.user_id,
    tm.status,
    p.full_name,
    u.email::text,
    r.key,
    r.name
  FROM tenant_memberships tm
  JOIN profiles p ON p.id = tm.user_id
  JOIN roles r ON r.id = tm.role_id
  JOIN auth.users u ON u.id = tm.user_id
  WHERE tm.tenant_id = current_tenant_id()
  ORDER BY
    CASE tm.status WHEN 'active' THEN 0 WHEN 'suspended' THEN 1 ELSE 2 END,
    p.full_name;
$$;

CREATE OR REPLACE FUNCTION revoke_tenant_invitation(
  p_invitation_id uuid
) RETURNS user_invitations
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_row user_invitations%ROWTYPE;
BEGIN
  v_tenant_id := current_tenant_id();

  IF v_tenant_id IS NULL OR NOT has_permission('members.manage') THEN
    RAISE EXCEPTION 'Usuário sem permissão para revogar convites.'
      USING ERRCODE = '42501';
  END IF;

  UPDATE user_invitations
  SET revoked_at = now()
  WHERE id = p_invitation_id
    AND tenant_id = v_tenant_id
    AND accepted_at IS NULL
    AND revoked_at IS NULL
  RETURNING * INTO v_row;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'Convite não encontrado.'
      USING ERRCODE = 'P0002';
  END IF;

  PERFORM log_audit(
    v_tenant_id,
    'member.invitation.revoked',
    'user_invitations',
    v_row.id::text,
    NULL,
    jsonb_build_object('email', v_row.email)
  );

  RETURN v_row;
END;
$$;

CREATE OR REPLACE FUNCTION set_tenant_membership_status(
  p_membership_id uuid,
  p_status text
) RETURNS tenant_memberships
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
  v_row tenant_memberships%ROWTYPE;
  v_role_key text;
BEGIN
  v_tenant_id := current_tenant_id();

  IF v_tenant_id IS NULL OR NOT has_permission('members.manage') THEN
    RAISE EXCEPTION 'Usuário sem permissão para gerenciar membros.'
      USING ERRCODE = '42501';
  END IF;

  IF p_status NOT IN ('active', 'suspended', 'removed') THEN
    RAISE EXCEPTION 'Status inválido: %', p_status
      USING ERRCODE = '22023';
  END IF;

  SELECT tm.*
  INTO v_row
  FROM tenant_memberships tm
  JOIN roles r ON r.id = tm.role_id
  WHERE tm.id = p_membership_id
    AND tm.tenant_id = v_tenant_id;

  SELECT r.key
  INTO v_role_key
  FROM tenant_memberships tm
  JOIN roles r ON r.id = tm.role_id
  WHERE tm.id = p_membership_id
    AND tm.tenant_id = v_tenant_id;

  IF v_row.id IS NULL THEN
    RAISE EXCEPTION 'Membership não encontrada.'
      USING ERRCODE = 'P0002';
  END IF;

  IF v_role_key = 'tenant_owner' AND p_status <> 'active' THEN
    RAISE EXCEPTION 'O proprietário da empresa não pode ser suspenso ou removido.'
      USING ERRCODE = 'P0001';
  END IF;

  UPDATE tenant_memberships
  SET status = p_status
  WHERE id = p_membership_id
  RETURNING * INTO v_row;

  PERFORM log_audit(
    v_tenant_id,
    'member.status.updated',
    'tenant_memberships',
    v_row.id::text,
    NULL,
    jsonb_build_object('status', p_status)
  );

  RETURN v_row;
END;
$$;

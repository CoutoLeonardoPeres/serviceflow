-- =============================================================================
-- Migration: 0027_accept_invitation
-- Descrição: Aceite seguro de convite por token após autenticação
-- Aplicar em: development, staging, production
-- Rollback: supabase/rollbacks/0027_accept_invitation_rollback.sql
-- =============================================================================

CREATE OR REPLACE FUNCTION accept_tenant_invitation(
  p_token text
) RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_hash text;
  v_invitation user_invitations%ROWTYPE;
  v_role_key text;
  v_user_email text;
  v_membership_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'Usuário não autenticado.'
      USING ERRCODE = '42501';
  END IF;

  IF p_token IS NULL OR btrim(p_token) = '' THEN
    RAISE EXCEPTION 'Convite inválido.'
      USING ERRCODE = '22023';
  END IF;

  v_hash := encode(digest(btrim(p_token), 'sha256'), 'hex');

  SELECT *
    INTO v_invitation
  FROM user_invitations ui
  WHERE ui.token_hash = v_hash
  LIMIT 1;

  IF v_invitation.id IS NULL THEN
    RAISE EXCEPTION 'Convite não encontrado.'
      USING ERRCODE = 'P0002';
  END IF;

  IF v_invitation.revoked_at IS NOT NULL THEN
    RAISE EXCEPTION 'Este convite já foi revogado.'
      USING ERRCODE = 'P0001';
  END IF;

  IF v_invitation.accepted_at IS NOT NULL THEN
    RAISE EXCEPTION 'Este convite já foi utilizado.'
      USING ERRCODE = 'P0001';
  END IF;

  IF v_invitation.expires_at < now() THEN
    RAISE EXCEPTION 'Este convite expirou.'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT lower(u.email::text)
    INTO v_user_email
  FROM auth.users u
  WHERE u.id = auth.uid();

  IF v_user_email IS NULL OR v_user_email <> lower(v_invitation.email) THEN
    RAISE EXCEPTION 'O convite pertence a outro e-mail.'
      USING ERRCODE = 'P0001';
  END IF;

  SELECT r.key
    INTO v_role_key
  FROM roles r
  WHERE r.id = v_invitation.role_id;

  SELECT tm.id
    INTO v_membership_id
  FROM tenant_memberships tm
  WHERE tm.tenant_id = v_invitation.tenant_id
    AND tm.user_id = auth.uid()
  LIMIT 1;

  IF v_membership_id IS NULL THEN
    INSERT INTO tenant_memberships (tenant_id, user_id, role_id, status)
    VALUES (v_invitation.tenant_id, auth.uid(), v_invitation.role_id, 'active')
    RETURNING id INTO v_membership_id;
  ELSE
    UPDATE tenant_memberships
    SET role_id = v_invitation.role_id,
        status = 'active'
    WHERE id = v_membership_id;
  END IF;

  UPDATE user_invitations
  SET accepted_at = now()
  WHERE id = v_invitation.id;

  PERFORM log_audit(
    v_invitation.tenant_id,
    'member.invitation.accepted',
    'user_invitations',
    v_invitation.id::text,
    NULL,
    jsonb_build_object(
      'email', v_invitation.email,
      'role_key', v_role_key
    )
  );

  RETURN v_invitation.tenant_id;
END;
$$;

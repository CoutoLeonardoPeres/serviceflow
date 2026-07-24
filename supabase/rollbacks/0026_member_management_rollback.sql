DROP FUNCTION IF EXISTS set_tenant_membership_status(uuid, text);
DROP FUNCTION IF EXISTS revoke_tenant_invitation(uuid);
DROP FUNCTION IF EXISTS list_tenant_members();
DROP FUNCTION IF EXISTS create_tenant_invitation(text, text, integer);

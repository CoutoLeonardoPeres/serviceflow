-- =============================================================================
-- Rollback: 0001_foundation
-- ATENÇÃO: destrói TODOS os dados das tabelas abaixo. Usar só em dev/staging.
-- =============================================================================

-- Ordem inversa de dependência
DROP TABLE IF EXISTS audit_logs           CASCADE;
DROP TABLE IF EXISTS platform_admins      CASCADE;
DROP TABLE IF EXISTS user_invitations     CASCADE;
DROP TABLE IF EXISTS tenant_memberships   CASCADE;
DROP TABLE IF EXISTS role_permissions     CASCADE;
DROP TABLE IF EXISTS permissions          CASCADE;
DROP TABLE IF EXISTS roles                CASCADE;
DROP TABLE IF EXISTS profiles             CASCADE;
DROP TABLE IF EXISTS tenant_sequences     CASCADE;
DROP TABLE IF EXISTS tenant_settings      CASCADE;
DROP TABLE IF EXISTS tenants              CASCADE;

-- Funções
DROP FUNCTION IF EXISTS current_tenant_id();
DROP FUNCTION IF EXISTS has_permission(text);
DROP FUNCTION IF EXISTS next_sequence(uuid, text);
DROP FUNCTION IF EXISTS log_audit(uuid, text, text, text, jsonb, jsonb, jsonb);
DROP FUNCTION IF EXISTS create_tenant_with_owner(text, text, uuid);
DROP FUNCTION IF EXISTS _sf_update_updated_at();
DROP FUNCTION IF EXISTS _sf_handle_new_user();

-- Triggers em auth.users (criado em 0001)
DROP TRIGGER IF EXISTS trg_on_auth_user_created ON auth.users;

-- Rollback: 0037_quotation_versioning
--
-- ATENCAO — ordem de rollback:
--   0039 substituiu create_new_quotation_version (adicionando log_audit). Se 0039
--   estiver aplicada, rode 0039_permissions_and_audit_rollback.sql ANTES deste
--   script.
--
-- Nao ha perda de dados: 0037 so criou funcoes. As versoes de orcamento em
-- quotation_versions vieram de 0005 e permanecem intactas.

DROP FUNCTION IF EXISTS list_quotation_versions(uuid);
DROP FUNCTION IF EXISTS create_new_quotation_version(uuid, jsonb, text);

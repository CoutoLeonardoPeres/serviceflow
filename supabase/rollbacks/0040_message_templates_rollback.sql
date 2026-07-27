-- Rollback: 0040_message_templates
--
-- ATENCAO — ordem de rollback:
--   0041 substituiu seed_default_message_templates (adicionando o template de
--   pesquisa). Se 0041 estiver aplicada, rode
--   0041_satisfaction_public_survey_rollback.sql ANTES deste script.
--
-- PERDA DE DADOS: remove os templates de mensagem do tenant e todo o historico
-- de comunicacoes registradas (communication_logs). Faca dump antes se o
-- historico de contatos com clientes importar.

DROP FUNCTION IF EXISTS seed_default_message_templates(uuid);
-- Assinatura: (customer_id, channel, body_preview, subject, related_entity,
--              related_entity_id, template_id, status)
DROP FUNCTION IF EXISTS log_communication(uuid, text, text, text, text, uuid, uuid, text);

DROP POLICY IF EXISTS "communication_logs_insert" ON communication_logs;
DROP POLICY IF EXISTS "communication_logs_select" ON communication_logs;
DROP INDEX IF EXISTS idx_communication_logs_entity;
DROP INDEX IF EXISTS idx_communication_logs_customer;
DROP INDEX IF EXISTS idx_communication_logs_tenant;
DROP TABLE IF EXISTS communication_logs;

DROP POLICY IF EXISTS "message_templates_delete" ON message_templates;
DROP POLICY IF EXISTS "message_templates_update" ON message_templates;
DROP POLICY IF EXISTS "message_templates_insert" ON message_templates;
DROP POLICY IF EXISTS "message_templates_select" ON message_templates;
DROP INDEX IF EXISTS idx_message_templates_tenant;
DROP TABLE IF EXISTS message_templates;

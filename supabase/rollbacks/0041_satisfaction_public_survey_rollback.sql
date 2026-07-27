-- Rollback: 0041_satisfaction_public_survey
--
-- Remove o fluxo publico de pesquisa. Nao afeta work_order_satisfaction (0014):
-- respostas ja coletadas permanecem, inclusive as vindas de link publico.
--
-- Alem de remover o que 0041 criou, este script:
--   * apaga o template "Pesquisa de satisfacao" inserido pelo backfill;
--   * restaura a versao 0040 de seed_default_message_templates (que 0041
--     substituiu para incluir aquele template).

DROP FUNCTION IF EXISTS submit_public_satisfaction(text, integer, text, text);
DROP FUNCTION IF EXISTS get_public_satisfaction_context(text);
DROP FUNCTION IF EXISTS revoke_satisfaction_public_link(uuid);
DROP FUNCTION IF EXISTS create_satisfaction_public_link(uuid, timestamptz);
DROP POLICY IF EXISTS "satisfaction_public_links_select" ON satisfaction_public_links;
DROP TABLE IF EXISTS satisfaction_public_links;

DELETE FROM message_templates WHERE name = 'Pesquisa de satisfacao';

-- ══════════════════════════════════════════════════════════════════════════
-- Restaura de 0040_message_templates.sql: seed_default_message_templates
-- ══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION seed_default_message_templates(p_tenant_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- Verifica se já existem templates (idempotente)
  IF EXISTS (SELECT 1 FROM message_templates WHERE tenant_id = p_tenant_id) THEN
    RETURN;
  END IF;

  INSERT INTO message_templates(tenant_id, name, channel, body) VALUES
    (p_tenant_id,
     'Confirmação de agendamento',
     'whatsapp',
     'Olá, {{customer_name}}! Confirmamos seu agendamento para o serviço "{{service_title}}". Qualquer dúvida, estamos à disposição. — {{company_name}}'),

    (p_tenant_id,
     'Orçamento enviado',
     'whatsapp',
     'Olá, {{customer_name}}! Seu orçamento nº {{quotation_number}} no valor de R$ {{amount}} está disponível para aprovação: {{link}} — {{company_name}}'),

    (p_tenant_id,
     'OS concluída',
     'whatsapp',
     'Olá, {{customer_name}}! A ordem de serviço nº {{work_order_number}} foi concluída. Agradecemos a preferência! — {{company_name}}'),

    (p_tenant_id,
     'Cobrança pendente',
     'whatsapp',
     'Olá, {{customer_name}}! Identificamos uma cobrança pendente de R$ {{amount}}. Para regularizar, entre em contato. — {{company_name}}'),

    (p_tenant_id,
     'Orçamento enviado (e-mail)',
     'email',
     'Prezado(a) {{customer_name}},\n\nSegue seu orçamento nº {{quotation_number}} no valor de R$ {{amount}}.\n\nAcesse pelo link: {{link}}\n\nAtenciosamente,\n{{company_name}}');
END;
$$;

COMMENT ON FUNCTION seed_default_message_templates IS
  'Insere templates padrão para um novo tenant. Idempotente.';

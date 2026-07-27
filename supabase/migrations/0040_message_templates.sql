-- ============================================================
-- 0040_message_templates.sql
-- F2-P3: Templates de mensagem + registro de comunicação
--
-- Envio real: fora do escopo MVP (ADR-012).
-- WhatsApp: deep link wa.me. E-mail: deep link mailto.
-- Esta migration cria a estrutura de dados e RPC de registro.
-- ============================================================

-- ── Tabela: message_templates ─────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS message_templates (
  id          uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id   uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  name        text        NOT NULL CHECK (char_length(name) BETWEEN 1 AND 100),
  channel     text        NOT NULL CHECK (channel IN ('whatsapp', 'email', 'generic')),
  subject     text        CHECK (subject IS NULL OR char_length(subject) <= 200),
  body        text        NOT NULL CHECK (char_length(body) BETWEEN 1 AND 2000),
  -- Variáveis suportadas: {{customer_name}}, {{quotation_number}},
  -- {{work_order_number}}, {{amount}}, {{company_name}}, {{link}}
  is_active   boolean     NOT NULL DEFAULT true,
  created_by  uuid        REFERENCES auth.users(id),
  created_at  timestamptz NOT NULL DEFAULT now(),
  updated_at  timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_message_templates_tenant
  ON message_templates(tenant_id, channel, is_active);

ALTER TABLE message_templates ENABLE ROW LEVEL SECURITY;

CREATE POLICY "message_templates_select" ON message_templates
  FOR SELECT TO authenticated
  USING (tenant_id = current_tenant_id() AND has_permission('customers.read'));

CREATE POLICY "message_templates_insert" ON message_templates
  FOR INSERT TO authenticated
  WITH CHECK (tenant_id = current_tenant_id() AND has_permission('customers.write'));

CREATE POLICY "message_templates_update" ON message_templates
  FOR UPDATE TO authenticated
  USING (tenant_id = current_tenant_id() AND has_permission('customers.write'))
  WITH CHECK (tenant_id = current_tenant_id() AND has_permission('customers.write'));

CREATE POLICY "message_templates_delete" ON message_templates
  FOR DELETE TO authenticated
  USING (tenant_id = current_tenant_id() AND has_permission('customers.write'));

-- ── Tabela: communication_logs ────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS communication_logs (
  id                uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id         uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  customer_id       uuid        REFERENCES customers(id) ON DELETE SET NULL,
  channel           text        NOT NULL CHECK (channel IN ('whatsapp', 'email', 'generic', 'phone')),
  direction         text        NOT NULL DEFAULT 'out' CHECK (direction IN ('in', 'out')),
  status            text        NOT NULL DEFAULT 'sent' CHECK (status IN ('sent', 'draft', 'failed')),
  subject           text        CHECK (subject IS NULL OR char_length(subject) <= 200),
  body_preview      text        CHECK (body_preview IS NULL OR char_length(body_preview) <= 500),
  related_entity    text        CHECK (related_entity IN (
                                  'quotations', 'work_orders', 'service_requests',
                                  'appointments', NULL
                                )),
  related_entity_id uuid,
  template_id       uuid        REFERENCES message_templates(id) ON DELETE SET NULL,
  created_by        uuid        REFERENCES auth.users(id),
  created_at        timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_communication_logs_tenant
  ON communication_logs(tenant_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_communication_logs_customer
  ON communication_logs(customer_id, created_at DESC)
  WHERE customer_id IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_communication_logs_entity
  ON communication_logs(related_entity, related_entity_id)
  WHERE related_entity IS NOT NULL;

ALTER TABLE communication_logs ENABLE ROW LEVEL SECURITY;

CREATE POLICY "communication_logs_select" ON communication_logs
  FOR SELECT TO authenticated
  USING (tenant_id = current_tenant_id() AND has_permission('customers.read'));

CREATE POLICY "communication_logs_insert" ON communication_logs
  FOR INSERT TO authenticated
  WITH CHECK (tenant_id = current_tenant_id() AND has_permission('customers.write'));

-- Logs são imutáveis (sem update/delete)

-- ── RPC: log_communication ────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION log_communication(
  p_customer_id       UUID,
  p_channel           TEXT,
  p_body_preview      TEXT    DEFAULT NULL,
  p_subject           TEXT    DEFAULT NULL,
  p_related_entity    TEXT    DEFAULT NULL,
  p_related_entity_id UUID    DEFAULT NULL,
  p_template_id       UUID    DEFAULT NULL,
  p_status            TEXT    DEFAULT 'sent'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id UUID;
  v_log_id    UUID;
BEGIN
  -- Identifica tenant pelo customer
  SELECT tenant_id INTO v_tenant_id
    FROM customers
   WHERE id = p_customer_id;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Cliente não encontrado.'
      USING ERRCODE = 'P0001';
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM tenant_memberships
     WHERE user_id   = auth.uid()
       AND tenant_id = v_tenant_id
       AND status    = 'active'
  ) THEN
    RAISE EXCEPTION 'Sem permissão.'
      USING ERRCODE = '42501';
  END IF;

  IF NOT has_permission('customers.write') THEN
    RAISE EXCEPTION 'Permissão customers.write necessária.'
      USING ERRCODE = '42501';
  END IF;

  INSERT INTO communication_logs(
    tenant_id, customer_id, channel, status,
    subject, body_preview, related_entity, related_entity_id,
    template_id, created_by
  )
  VALUES (
    v_tenant_id, p_customer_id, p_channel, p_status,
    p_subject, p_body_preview, p_related_entity, p_related_entity_id,
    p_template_id, auth.uid()
  )
  RETURNING id INTO v_log_id;

  PERFORM log_audit(
    v_tenant_id,
    'communication.sent',
    'customers',
    p_customer_id::text,
    NULL,
    jsonb_build_object(
      'channel', p_channel,
      'status',  p_status,
      'related_entity', p_related_entity,
      'related_entity_id', p_related_entity_id
    )
  );

  RETURN v_log_id;
END;
$$;

COMMENT ON FUNCTION log_communication IS
  'Registra um contato com cliente (WhatsApp deep link, e-mail, ligação). Não envia nada — apenas loga.';

-- ── Seed de templates padrão por tenant (função auxiliar) ─────────────────────
-- Não insere automaticamente — chamada pela UI ao criar tenant ou manualmente.

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

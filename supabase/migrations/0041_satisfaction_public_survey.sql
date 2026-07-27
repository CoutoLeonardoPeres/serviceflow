-- =============================================================================
-- Migration: 0041_satisfaction_public_survey
-- Descricao: Pesquisa de satisfacao respondida pelo proprio cliente via link
--            publico com token opaco e expiracao — F2-P5
-- Depende de: 0008_work_orders, 0014_customer_satisfaction, 0039_permissions_and_audit
-- Rollback: supabase/rollbacks/0041_satisfaction_public_survey_rollback.sql
--
-- SEGURANCA — endpoint anonimo:
--   Este e o segundo caminho de escrita nao autenticado do sistema (o primeiro e
--   decide_public_quotation, 0006). Mitigacoes aplicadas:
--     * Token opaco de 32 bytes aleatorios; armazenado apenas como SHA-256.
--       O token em claro so existe na resposta do RPC de criacao.
--     * Expiracao obrigatoria (padrao 30 dias) + revogacao manual.
--     * Link so pode ser gerado para OS com status 'done'.
--     * get_public_satisfaction_context devolve dados minimos: numero da OS,
--       titulo do servico e nome da empresa. NAO expoe valores, endereco,
--       telefone, e-mail nem qualquer dado do cliente.
--     * Escrita restrita a rating/contact_name/comment da propria OS do token.
--       O tenant_id vem do link, nunca do cliente.
--   Nao aplicado nesta entrega (decisao do produto, registrada em PROJECT_STATE):
--     * Rate limit por IP (exigiria Edge Function).
--     * Resposta unica — o cliente pode corrigir a nota enquanto o link valer.
-- =============================================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

-- ── Tabela de links publicos de pesquisa ─────────────────────────────────────

CREATE TABLE IF NOT EXISTS satisfaction_public_links (
  id             uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  tenant_id      uuid        NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
  work_order_id  uuid        NOT NULL REFERENCES work_orders(id) ON DELETE CASCADE,
  token_hash     text        NOT NULL UNIQUE,
  expires_at     timestamptz NOT NULL,
  revoked_at     timestamptz,
  use_count      integer     NOT NULL DEFAULT 0 CHECK (use_count >= 0),
  last_access_at timestamptz,
  responded_at   timestamptz,
  created_at     timestamptz NOT NULL DEFAULT now(),
  created_by     uuid        REFERENCES auth.users(id)
);

CREATE INDEX IF NOT EXISTS idx_satisfaction_public_links_wo
  ON satisfaction_public_links (work_order_id);
CREATE INDEX IF NOT EXISTS idx_satisfaction_public_links_tenant
  ON satisfaction_public_links (tenant_id, created_at DESC);

ALTER TABLE satisfaction_public_links ENABLE ROW LEVEL SECURITY;

-- Leitura apenas pelo tenant dono, com permissao de leitura de OS.
-- Nao ha policy de INSERT/UPDATE/DELETE: toda escrita passa pelos RPCs
-- SECURITY DEFINER abaixo.
DROP POLICY IF EXISTS "satisfaction_public_links_select" ON satisfaction_public_links;
CREATE POLICY "satisfaction_public_links_select" ON satisfaction_public_links
  FOR SELECT
  USING (tenant_id = current_tenant_id() AND has_permission('work_orders.read'));

-- ── Geracao do link (autenticado) ────────────────────────────────────────────

CREATE OR REPLACE FUNCTION create_satisfaction_public_link(
  p_work_order_id uuid,
  p_expires_at    timestamptz DEFAULT NULL
) RETURNS text LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id  uuid;
  v_work_order work_orders;
  v_token      text;
  v_expires_at timestamptz;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL
     OR NOT (has_permission('work_orders.execute') OR has_permission('work_orders.manage')) THEN
    RAISE EXCEPTION 'Permissao insuficiente para gerar link de pesquisa.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_work_order
  FROM work_orders
  WHERE id = p_work_order_id AND tenant_id = v_tenant_id;

  IF v_work_order.id IS NULL THEN
    RAISE EXCEPTION 'OS nao encontrada.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF v_work_order.status <> 'done' THEN
    RAISE EXCEPTION 'A pesquisa so pode ser enviada apos concluir a OS.'
      USING ERRCODE = 'check_violation';
  END IF;

  v_expires_at := COALESCE(p_expires_at, now() + interval '30 days');

  IF v_expires_at <= now() THEN
    RAISE EXCEPTION 'Data de expiracao invalida.'
      USING ERRCODE = 'check_violation';
  END IF;

  -- Revoga links anteriores da mesma OS: apenas um link valido por vez.
  UPDATE satisfaction_public_links
  SET revoked_at = now()
  WHERE work_order_id = p_work_order_id
    AND revoked_at IS NULL;

  v_token := encode(extensions.gen_random_bytes(32), 'hex');

  INSERT INTO satisfaction_public_links (
    tenant_id, work_order_id, token_hash, expires_at, created_by
  ) VALUES (
    v_tenant_id,
    p_work_order_id,
    encode(extensions.digest(v_token, 'sha256'), 'hex'),
    v_expires_at,
    auth.uid()
  );

  PERFORM log_audit(
    v_tenant_id,
    'work_order.satisfaction_link.created',
    'work_orders',
    p_work_order_id::text,
    NULL,
    jsonb_build_object('expires_at', v_expires_at)
  );

  -- Token em claro retornado uma unica vez; o banco guarda so o hash.
  RETURN v_token;
END;
$$;

-- ── Revogacao do link (autenticado) ──────────────────────────────────────────

CREATE OR REPLACE FUNCTION revoke_satisfaction_public_link(p_work_order_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL
     OR NOT (has_permission('work_orders.execute') OR has_permission('work_orders.manage')) THEN
    RAISE EXCEPTION 'Permissao insuficiente para revogar link de pesquisa.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  UPDATE satisfaction_public_links
  SET revoked_at = now()
  WHERE work_order_id = p_work_order_id
    AND tenant_id = v_tenant_id
    AND revoked_at IS NULL;

  PERFORM log_audit(
    v_tenant_id,
    'work_order.satisfaction_link.revoked',
    'work_orders',
    p_work_order_id::text,
    NULL,
    jsonb_build_object()
  );
END;
$$;

-- ── Contexto publico (anonimo) ───────────────────────────────────────────────
-- Devolve o minimo necessario para o cliente saber o que esta avaliando.
-- NAO retorna valores, endereco, telefone, e-mail ou dados do cliente.

CREATE OR REPLACE FUNCTION get_public_satisfaction_context(p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_link        satisfaction_public_links;
  v_work_order  work_orders;
  v_company     text;
  v_existing    work_order_satisfaction;
BEGIN
  SELECT * INTO v_link
  FROM satisfaction_public_links
  WHERE token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
    AND revoked_at IS NULL
    AND expires_at > now();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Link invalido ou expirado.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  UPDATE satisfaction_public_links
  SET use_count = use_count + 1,
      last_access_at = now()
  WHERE id = v_link.id;

  SELECT * INTO v_work_order
  FROM work_orders
  WHERE id = v_link.work_order_id;

  SELECT name INTO v_company
  FROM tenants
  WHERE id = v_link.tenant_id;

  SELECT * INTO v_existing
  FROM work_order_satisfaction
  WHERE work_order_id = v_link.work_order_id;

  RETURN jsonb_build_object(
    'work_order_number', v_work_order.number,
    'service_title',     v_work_order.title,
    'company_name',      v_company,
    'completed_at',      v_work_order.updated_at,
    'already_answered',  v_existing.id IS NOT NULL,
    'current_rating',    v_existing.rating
  );
END;
$$;

-- ── Envio da resposta (anonimo) ──────────────────────────────────────────────
-- tenant_id e work_order_id vem SEMPRE do link, nunca do cliente.

CREATE OR REPLACE FUNCTION submit_public_satisfaction(
  p_token        text,
  p_rating       integer,
  p_contact_name text DEFAULT NULL,
  p_comment      text DEFAULT NULL
) RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_link       satisfaction_public_links;
  v_work_order work_orders;
BEGIN
  IF p_rating IS NULL OR p_rating < 1 OR p_rating > 5 THEN
    RAISE EXCEPTION 'Nota de satisfacao invalida.'
      USING ERRCODE = 'check_violation';
  END IF;

  SELECT * INTO v_link
  FROM satisfaction_public_links
  WHERE token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
    AND revoked_at IS NULL
    AND expires_at > now();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Link invalido ou expirado.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  SELECT * INTO v_work_order
  FROM work_orders
  WHERE id = v_link.work_order_id;

  IF v_work_order.id IS NULL THEN
    RAISE EXCEPTION 'OS nao encontrada.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  INSERT INTO work_order_satisfaction (
    tenant_id, work_order_id, customer_id, rating, contact_name, comment
  ) VALUES (
    v_link.tenant_id,
    v_link.work_order_id,
    v_work_order.customer_id,
    p_rating,
    NULLIF(LEFT(TRIM(COALESCE(p_contact_name, '')), 160), ''),
    NULLIF(LEFT(TRIM(COALESCE(p_comment, '')), 1000), '')
  )
  ON CONFLICT (work_order_id) DO UPDATE
  SET rating       = EXCLUDED.rating,
      contact_name = EXCLUDED.contact_name,
      comment      = EXCLUDED.comment,
      updated_at   = now();

  UPDATE satisfaction_public_links
  SET responded_at = now()
  WHERE id = v_link.id;

  INSERT INTO work_order_events (
    tenant_id, work_order_id, event_type, notes, created_by
  ) VALUES (
    v_link.tenant_id,
    v_link.work_order_id,
    'note',
    'Pesquisa respondida pelo cliente: ' || p_rating::text || '/5',
    NULL
  );

  PERFORM log_audit(
    v_link.tenant_id,
    'work_order.satisfaction.public_submitted',
    'work_order_satisfaction',
    v_link.work_order_id::text,
    NULL,
    jsonb_build_object('rating', p_rating, 'source', 'public_link')
  );
END;
$$;

-- ── Template padrao de pesquisa ──────────────────────────────────────────────
-- Backfill: tenants que ja rodaram seed_default_message_templates nao receberiam
-- o novo template, porque aquela funcao sai cedo se ja existir qualquer template.
-- Este INSERT cobre os tenants existentes; o seed atualizado abaixo cobre os novos.

INSERT INTO message_templates (tenant_id, name, channel, body)
SELECT
  t.id,
  'Pesquisa de satisfacao',
  'whatsapp',
  'Olá, {{customer_name}}! A ordem de serviço nº {{work_order_number}} foi ' ||
  'concluída. Poderia avaliar nosso atendimento? Leva menos de um minuto: ' ||
  '{{link}} — {{company_name}}'
FROM tenants t
WHERE EXISTS (
        SELECT 1 FROM message_templates m WHERE m.tenant_id = t.id
      )
  AND NOT EXISTS (
        SELECT 1 FROM message_templates m
        WHERE m.tenant_id = t.id AND m.name = 'Pesquisa de satisfacao'
      );

CREATE OR REPLACE FUNCTION seed_default_message_templates(p_tenant_id UUID)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
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
     'Pesquisa de satisfacao',
     'whatsapp',
     'Olá, {{customer_name}}! A ordem de serviço nº {{work_order_number}} foi concluída. Poderia avaliar nosso atendimento? Leva menos de um minuto: {{link}} — {{company_name}}'),

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

-- ── Insercao anonima em work_order_satisfaction ──────────────────────────────
-- O trigger _sf_set_work_order_satisfaction_meta (0014) sobrescreve tenant_id
-- com current_tenant_id() quando auth.uid() nao e nulo. No caminho anonimo
-- auth.uid() E nulo, entao ele exige tenant_id explicito — que o RPC fornece a
-- partir do link. Nenhuma alteracao no trigger e necessaria.
--
-- As policies de 0014 nao permitem INSERT anonimo, mas os RPCs acima sao
-- SECURITY DEFINER e rodam como owner, contornando RLS de forma controlada:
-- a unica porta de entrada e um token valido e nao expirado.

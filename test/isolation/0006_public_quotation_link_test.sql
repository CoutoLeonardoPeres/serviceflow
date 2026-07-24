-- =============================================================================
-- Teste SQL manual: link publico de orcamento — Entrega 6
-- Objetivo:
--   1. Gerar link publico com usuario autorizado no tenant.
--   2. Abrir orcamento pelo token publico.
--   3. Revogar links ativos do orcamento.
--   4. Confirmar que o token revogado nao abre mais.
--
-- Pre-requisitos:
--   - Substituir os placeholders abaixo por UUIDs reais do seed/ambiente.
--   - Executar como usuario autenticado com permissao `quotations.send`.
-- =============================================================================

BEGIN;

-- TODO: substituir antes da execucao real.
-- SELECT set_config('request.jwt.claim.sub', '<USER_UUID_COM_QUOTATIONS_SEND>', true);

DO $$
DECLARE
  v_quotation_id uuid := '<QUOTATION_UUID>'::uuid;
  v_token text;
  v_payload jsonb;
  v_revoked integer;
BEGIN
  v_token := create_quotation_public_link(v_quotation_id);

  v_payload := get_public_quotation(v_token);
  IF (v_payload->>'id')::uuid <> v_quotation_id THEN
    RAISE EXCEPTION 'Token publico retornou orcamento inesperado.';
  END IF;

  v_revoked := revoke_quotation_public_links(v_quotation_id);
  IF v_revoked < 1 THEN
    RAISE EXCEPTION 'Nenhum link publico foi revogado.';
  END IF;

  BEGIN
    PERFORM get_public_quotation(v_token);
    RAISE EXCEPTION 'Token revogado ainda abriu o orcamento.';
  EXCEPTION
    WHEN insufficient_privilege THEN
      RAISE NOTICE 'OK: token revogado foi bloqueado.';
  END;
END $$;

ROLLBACK;

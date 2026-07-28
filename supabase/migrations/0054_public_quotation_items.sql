-- =============================================================================
-- Migration: 0054_public_quotation_items
-- Descricao: Link publico do orcamento devolve as linhas — F6-P0
-- Depende de: 0005_quotations, 0006_quotation_public_flow
-- Rollback: supabase/rollbacks/0054_public_quotation_items_rollback.sql
--
-- ORIGEM: `get_public_quotation` devolvia `to_jsonb(v_quote)` — so a linha de
-- `quotations`, com totais e nenhum item. A pagina que o cliente abre mostrava
-- uma proposta sem dizer o que esta sendo cotado, e o app tentava completar a
-- informacao consultando `service_requests`/`customer_addresses` direto do
-- cliente. Essas consultas rodam como `anon`, que nao passa pelas policies —
-- entao nao traziam nada e, dependendo do GRANT, derrubavam a tela inteira
-- com "Link invalido".
--
-- DECISAO: tudo que a pagina publica mostra sai desta funcao, que e
-- SECURITY DEFINER e ja valida o token. O app nao faz nenhuma consulta
-- adicional em tabela protegida no fluxo publico.
-- =============================================================================

CREATE OR REPLACE FUNCTION get_public_quotation(p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_link quotation_public_links;
  v_quote quotations;
  v_customer_name text;
  v_request_title text;
  v_items jsonb;
BEGIN
  SELECT * INTO v_link
  FROM quotation_public_links
  WHERE token_hash = encode(extensions.digest(p_token, 'sha256'), 'hex')
    AND revoked_at IS NULL
    AND expires_at > now();

  IF NOT FOUND THEN
    RAISE EXCEPTION 'Link invalido ou expirado.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  UPDATE quotation_public_links
  SET use_count = use_count + 1,
      last_access_at = now()
  WHERE id = v_link.id;

  UPDATE quotations
  SET status = CASE WHEN status = 'sent' THEN 'viewed' ELSE status END
  WHERE id = v_link.quotation_id
  RETURNING * INTO v_quote;

  SELECT name INTO v_customer_name FROM customers WHERE id = v_quote.customer_id;
  SELECT title INTO v_request_title FROM service_requests WHERE id = v_quote.request_id;

  -- Itens da versao que o link aponta: se o orcamento for revisado depois, o
  -- link antigo continua mostrando exatamente o que foi enviado.
  SELECT COALESCE(
           jsonb_agg(
             jsonb_build_object(
               'id', qi.id,
               'quotation_id', qi.quotation_id,
               'version_id', qi.version_id,
               'kind', qi.kind,
               'description', qi.description,
               'quantity', qi.quantity,
               'unit_price_cents', qi.unit_price_cents,
               'unit_cost_cents', qi.unit_cost_cents,
               'created_at', qi.created_at
             )
             ORDER BY qi.created_at, qi.id
           ),
           '[]'::jsonb
         )
    INTO v_items
  FROM quotation_items qi
  WHERE qi.quotation_id = v_quote.id
    AND qi.version_id = v_link.version_id;

  RETURN to_jsonb(v_quote)
    || jsonb_build_object('customers', jsonb_build_object('name', v_customer_name))
    || jsonb_build_object('service_requests', CASE WHEN v_request_title IS NULL THEN NULL ELSE jsonb_build_object('title', v_request_title) END)
    || jsonb_build_object('quotation_items', v_items);
END;
$$;

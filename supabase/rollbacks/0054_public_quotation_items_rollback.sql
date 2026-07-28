-- Rollback: 0054_public_quotation_items
--
-- Sem perda de dados: a migration só troca o corpo de `get_public_quotation`
-- (mesma assinatura). Restaura a versão da 0006, que devolve o orçamento sem
-- as linhas.
--
-- ATENÇÃO: com esta versão de volta, a página pública volta a mostrar a
-- proposta sem itens.

CREATE OR REPLACE FUNCTION get_public_quotation(p_token text)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_link quotation_public_links;
  v_quote quotations;
  v_customer_name text;
  v_request_title text;
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

  RETURN to_jsonb(v_quote)
    || jsonb_build_object('customers', jsonb_build_object('name', v_customer_name))
    || jsonb_build_object('service_requests', CASE WHEN v_request_title IS NULL THEN NULL ELSE jsonb_build_object('title', v_request_title) END);
END;
$$;

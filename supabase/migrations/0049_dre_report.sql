-- =============================================================================
-- Migration: 0049_dre_report
-- Descricao: DRE simples em regime de caixa — F4-P2 (ADR-026)
-- Depende de: 0001_foundation, 0013_financials_minimum, 0048_payables
-- Rollback: supabase/rollbacks/0049_dre_report_rollback.sql
--
-- Sem tabela nova: e so uma funcao de leitura que agrega o que ja existe em
-- payment_records (receita, o que o cliente pagou) e payable_payments
-- (despesa, o que foi pago a fornecedor), agrupado por mes. Regime de caixa,
-- nao competencia — ver ADR-026 para a limitacao aceita.
--
-- ponytail: meses sem nenhum pagamento nao aparecem (sem zero-preenchimento
-- via generate_series). Se o relatorio precisar mostrar todos os 12 meses do
-- ano mesmo vazios, o Flutter preenche os buracos na apresentacao — nao vale
-- complicar a query por isso agora.
-- =============================================================================

CREATE OR REPLACE FUNCTION get_dre_monthly(p_year integer)
RETURNS TABLE (
  month_start   date,
  revenue_cents bigint,
  expense_cents bigint,
  result_cents  bigint
) LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_tenant_id uuid;
BEGIN
  v_tenant_id := current_tenant_id();
  IF v_tenant_id IS NULL OR NOT has_permission('financials.read') THEN
    RAISE EXCEPTION 'Permissao financials.read necessaria.'
      USING ERRCODE = 'insufficient_privilege';
  END IF;

  IF p_year IS NULL THEN
    RAISE EXCEPTION 'Ano e obrigatorio.'
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN QUERY
  WITH revenue AS (
    SELECT
      date_trunc('month', pr.paid_at)::date AS month_start,
      SUM(pr.amount_cents)::bigint AS amount
    FROM payment_records pr
    WHERE pr.tenant_id = v_tenant_id
      AND extract(YEAR FROM pr.paid_at) = p_year
    GROUP BY 1
  ),
  expense AS (
    SELECT
      date_trunc('month', pp.paid_at)::date AS month_start,
      SUM(pp.amount_cents)::bigint AS amount
    FROM payable_payments pp
    WHERE pp.tenant_id = v_tenant_id
      AND extract(YEAR FROM pp.paid_at) = p_year
    GROUP BY 1
  )
  SELECT
    COALESCE(r.month_start, e.month_start) AS month_start,
    COALESCE(r.amount, 0)::bigint AS revenue_cents,
    COALESCE(e.amount, 0)::bigint AS expense_cents,
    (COALESCE(r.amount, 0) - COALESCE(e.amount, 0))::bigint AS result_cents
  FROM revenue r
  FULL OUTER JOIN expense e USING (month_start)
  ORDER BY 1;
END;
$$;

COMMENT ON FUNCTION get_dre_monthly(integer) IS
  'DRE simples em regime de caixa (ADR-026): receita = payment_records pagos, despesa = payable_payments pagos, por mes. Nao e competencia, nao tem CMV por venda nem plano de contas.';

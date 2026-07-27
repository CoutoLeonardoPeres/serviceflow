-- Rollback: 0036_cancellations
--
-- ATENCAO — ordem de rollback:
--   0039 substituiu cancel_quotation e cancel_work_order. Se 0039 estiver
--   aplicada, rode 0039_permissions_and_audit_rollback.sql ANTES deste script,
--   senao as funcoes ficarao orfas apontando para colunas que este script remove.
--
-- PERDA DE DADOS: remove as colunas de cancelamento e a tabela de historico de
-- status de orcamentos. Motivos de cancelamento ja registrados serao perdidos.
-- Faca dump de quotation_status_history antes, se o historico importar.

DROP FUNCTION IF EXISTS cancel_work_order(uuid, text);
DROP FUNCTION IF EXISTS cancel_quotation(uuid, text);

DROP POLICY IF EXISTS "quotation_status_history_select" ON quotation_status_history;
DROP INDEX IF EXISTS idx_quotation_status_history_quotation;
DROP TABLE IF EXISTS quotation_status_history;

DROP INDEX IF EXISTS idx_work_orders_cancelled_at;
DROP INDEX IF EXISTS idx_quotations_cancelled_at;

ALTER TABLE work_orders
  DROP COLUMN IF EXISTS cancellation_reason,
  DROP COLUMN IF EXISTS cancelled_at;

ALTER TABLE quotations
  DROP COLUMN IF EXISTS cancellation_reason,
  DROP COLUMN IF EXISTS cancelled_at;

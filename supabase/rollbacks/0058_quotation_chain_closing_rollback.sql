-- Rollback: 0058_quotation_chain_closing
--
-- Sem perda de dados: chamados já fechados pelos triggers continuam fechados,
-- e os registros em `quotation_status_history` permanecem. O que volta é o
-- comportamento anterior — OS concluída e orçamento recusado deixam o chamado
-- aberto para sempre, e não existe reabertura.
--
-- Nenhuma função de migration anterior foi substituída aqui, então este
-- rollback só remove o que a 0058 criou. Rodá-lo fora de ordem em relação a
-- 0056 é seguro: os dois triggers de `quotations` são independentes.

DROP TRIGGER IF EXISTS trg_work_order_done_closes_chain ON work_orders;
DROP TRIGGER IF EXISTS trg_quotation_refused_closes_chain ON quotations;

DROP FUNCTION IF EXISTS _sf_close_chain_on_work_order_done();
DROP FUNCTION IF EXISTS _sf_close_chain_on_quotation_refused();
DROP FUNCTION IF EXISTS reopen_quotation(uuid, text);
DROP FUNCTION IF EXISTS quotation_reopen_deadline(uuid);

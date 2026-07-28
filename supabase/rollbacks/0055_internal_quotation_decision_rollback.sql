-- Rollback: 0055_internal_quotation_decision
--
-- Sem perda de dados estruturais: as decisões já registradas continuam em
-- `quotation_approvals` e os status dos orçamentos ficam como estão. O que
-- some é a possibilidade de registrar a resposta do cliente pelo sistema —
-- volta a valer só a aprovação pelo link público.

DROP FUNCTION IF EXISTS decide_quotation(uuid, text, text, text);

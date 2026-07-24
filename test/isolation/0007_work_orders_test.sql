-- Roteiro manual E7 — substituir os placeholders por UUIDs reais do Supabase.
-- Objetivo:
-- 1. converter orçamento aprovado em OS;
-- 2. confirmar idempotência da conversão;
-- 3. bloquear orçamento não aprovado;
-- 4. registrar transição de execução.

BEGIN;

-- SELECT set_config('request.jwt.claim.sub', '<USER_UUID_COM_WORK_ORDERS_WRITE>', true);
-- SELECT set_config('request.jwt.claim.role', 'authenticated', true);

-- Conversão idempotente: duas chamadas devem retornar a mesma OS.
-- WITH first_call AS (
--   SELECT convert_approved_quotation_to_work_order('<QUOTATION_UUID_APROVADO>'::uuid) AS result
-- ),
-- second_call AS (
--   SELECT convert_approved_quotation_to_work_order('<QUOTATION_UUID_APROVADO>'::uuid) AS result
-- )
-- SELECT
--   (first_call.result->>'id') = (second_call.result->>'id') AS conversion_is_idempotent
-- FROM first_call, second_call;

-- Transição de execução.
-- SELECT transition_work_order('<WORK_ORDER_UUID>'::uuid, 'in_progress', 'Equipe iniciou atendimento.');
-- SELECT transition_work_order('<WORK_ORDER_UUID>'::uuid, 'done', 'Serviço concluído e conferido.');

ROLLBACK;

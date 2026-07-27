-- Rollback: 0038_work_order_returns
--
-- ATENCAO — ordem de rollback:
--   0039 substituiu create_return_work_order (adicionando log_audit). Se 0039
--   estiver aplicada, rode 0039_permissions_and_audit_rollback.sql ANTES deste
--   script.
--
-- PERDA DE DADOS: remove parent_work_order_id. O vinculo entre OS de retorno e
-- OS original sera perdido; as OS de retorno permanecem como OS avulsas.

DROP FUNCTION IF EXISTS create_return_work_order(uuid, text);

-- Contract: remove eventos 'return_created' antes de restringir a constraint,
-- senao o ADD CONSTRAINT falha com dados existentes.
DELETE FROM work_order_events WHERE event_type = 'return_created';

ALTER TABLE work_order_events
  DROP CONSTRAINT IF EXISTS work_order_events_event_type_check;

ALTER TABLE work_order_events
  ADD CONSTRAINT work_order_events_event_type_check
    CHECK (event_type IN (
      'created','converted_from_quotation','started',
      'paused','resumed','completed','cancelled','note'
    ));

DROP INDEX IF EXISTS idx_work_orders_parent;

ALTER TABLE work_orders
  DROP COLUMN IF EXISTS parent_work_order_id;

DROP FUNCTION IF EXISTS record_work_order_satisfaction(uuid, integer, text, text);
DROP TRIGGER IF EXISTS trg_work_order_satisfaction_meta ON work_order_satisfaction;
DROP FUNCTION IF EXISTS _sf_set_work_order_satisfaction_meta();
DROP TRIGGER IF EXISTS trg_work_order_satisfaction_updated_at ON work_order_satisfaction;
DROP TABLE IF EXISTS work_order_satisfaction;

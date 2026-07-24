DROP FUNCTION IF EXISTS transition_work_order(uuid, text, text);
DROP FUNCTION IF EXISTS convert_approved_quotation_to_work_order(uuid);
DROP FUNCTION IF EXISTS _work_order_json(uuid);
DROP TRIGGER IF EXISTS trg_work_orders_meta ON work_orders;
DROP FUNCTION IF EXISTS _sf_set_work_order_meta();
DROP TABLE IF EXISTS work_order_evidence;
DROP TABLE IF EXISTS work_order_events;
DROP TABLE IF EXISTS work_order_items;
DROP TABLE IF EXISTS work_orders;

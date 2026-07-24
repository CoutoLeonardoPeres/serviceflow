DROP FUNCTION IF EXISTS add_work_order_material(uuid, text, numeric, integer, integer);
DROP FUNCTION IF EXISTS record_work_order_time_entry(uuid, timestamptz, timestamptz, text);
DROP TABLE IF EXISTS work_order_materials;
DROP TABLE IF EXISTS work_order_time_entries;

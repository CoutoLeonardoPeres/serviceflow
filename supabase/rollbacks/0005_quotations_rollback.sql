DROP POLICY IF EXISTS "quotation_approvals_select" ON quotation_approvals;
DROP POLICY IF EXISTS "quotation_public_links_select" ON quotation_public_links;
DROP POLICY IF EXISTS "quotation_items_select" ON quotation_items;
DROP POLICY IF EXISTS "quotation_versions_select" ON quotation_versions;
DROP POLICY IF EXISTS "quotations_update" ON quotations;
DROP POLICY IF EXISTS "quotations_insert" ON quotations;
DROP POLICY IF EXISTS "quotations_select" ON quotations;

DROP FUNCTION IF EXISTS create_quotation(uuid, uuid, date, text, text, jsonb);
DROP FUNCTION IF EXISTS _sf_set_quotation_meta();

DROP TABLE IF EXISTS quotation_approvals;
DROP TABLE IF EXISTS quotation_public_links;
DROP TABLE IF EXISTS quotation_items;
ALTER TABLE IF EXISTS quotations DROP CONSTRAINT IF EXISTS fk_quotations_current_version;
DROP TABLE IF EXISTS quotation_versions;
DROP TABLE IF EXISTS quotations;

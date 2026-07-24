DROP POLICY IF EXISTS "visit_evidence_insert" ON visit_evidence;
DROP POLICY IF EXISTS "visit_evidence_select" ON visit_evidence;
DROP POLICY IF EXISTS "technical_visits_update" ON technical_visits;
DROP POLICY IF EXISTS "technical_visits_insert" ON technical_visits;
DROP POLICY IF EXISTS "technical_visits_select" ON technical_visits;
DROP POLICY IF EXISTS "appointment_assignments_update" ON appointment_assignments;
DROP POLICY IF EXISTS "appointment_assignments_insert" ON appointment_assignments;
DROP POLICY IF EXISTS "appointment_assignments_select" ON appointment_assignments;
DROP POLICY IF EXISTS "appointments_update" ON appointments;
DROP POLICY IF EXISTS "appointments_insert" ON appointments;
DROP POLICY IF EXISTS "appointments_select" ON appointments;

DROP FUNCTION IF EXISTS schedule_appointment(text, uuid, uuid, uuid, timestamptz, timestamptz, uuid, text);
DROP FUNCTION IF EXISTS list_tenant_technicians();
DROP FUNCTION IF EXISTS _sf_set_visit_evidence_meta();
DROP FUNCTION IF EXISTS _sf_set_technical_visit_meta();
DROP FUNCTION IF EXISTS _sf_set_appointment_assignment_meta();
DROP FUNCTION IF EXISTS _sf_set_appointment_meta();

DROP TABLE IF EXISTS visit_evidence;
DROP TABLE IF EXISTS technical_visits;
DROP TABLE IF EXISTS appointment_assignments;
DROP TABLE IF EXISTS appointments;

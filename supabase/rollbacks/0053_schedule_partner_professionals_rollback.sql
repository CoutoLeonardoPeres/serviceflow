-- Rollback: 0053_schedule_partner_professionals
--
-- PERDA DE DADOS: agendamentos de profissional SEM usuario vinculado ficam
-- invalidos ao restaurar `technician_user_id NOT NULL`. Este script cancela
-- esses atendimentos antes de restaurar a constraint — eles voltam para a
-- fila. Exporte antes se precisar:
--   COPY (SELECT a.* FROM appointments a
--         JOIN appointment_assignments aa ON aa.appointment_id = a.id
--         WHERE aa.technician_user_id IS NULL)
--   TO '/tmp/appointments_parceiros.csv' CSV HEADER;

-- 1. Cancela o que so existia graças a esta migration.
UPDATE appointments a
SET status = 'cancelled'
WHERE a.status <> 'cancelled'
  AND EXISTS (
    SELECT 1 FROM appointment_assignments aa
    WHERE aa.appointment_id = a.id
      AND aa.technician_user_id IS NULL
      AND aa.revoked_at IS NULL
  );

DELETE FROM appointment_assignments WHERE technician_user_id IS NULL;

-- 2. Estrutura
DROP INDEX IF EXISTS uq_appointment_active_professional;
DROP INDEX IF EXISTS idx_appointment_assignments_professional;

ALTER TABLE appointment_assignments
  DROP CONSTRAINT IF EXISTS chk_appointment_assignment_target;

ALTER TABLE appointment_assignments
  ALTER COLUMN technician_user_id SET NOT NULL;

ALTER TABLE appointment_assignments
  DROP COLUMN IF EXISTS professional_id;

DROP FUNCTION IF EXISTS _sf_professional_busy(uuid, uuid, timestamptz, timestamptz, uuid);

-- 3. Assinaturas: derruba as de 0053 e recria as de 0052.
DROP FUNCTION IF EXISTS schedule_appointment(
  text, uuid, uuid, uuid, timestamptz, timestamptz, uuid, text, uuid
);
DROP FUNCTION IF EXISTS assign_technician(uuid, uuid, uuid);
DROP FUNCTION IF EXISTS unassign_technician(uuid, uuid, uuid);

-- ATENCAO: reaplique manualmente as versoes de 0051/0052 destas funcoes —
-- estao em supabase/migrations/0051_appointment_events.sql (schedule_appointment,
-- cancel_appointment) e 0052_appointment_multi_technician.sql (assign_technician,
-- unassign_technician). Rodar este rollback sem reaplica-las deixa a agenda
-- sem RPC de agendamento.

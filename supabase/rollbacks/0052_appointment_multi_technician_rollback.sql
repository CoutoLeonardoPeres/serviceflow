-- Rollback: 0052_appointment_multi_technician
--
-- PERDA DE DADOS PARCIAL: os eventos 'technician_added'/'technician_removed'
-- ja gravados violam o CHECK restaurado. Este script os apaga. Exporte antes
-- se houver relatorio dependendo deles:
--   COPY (SELECT * FROM appointment_events
--          WHERE event_type IN ('technician_added','technician_removed'))
--   TO '/tmp/appointment_technician_events.csv' CSV HEADER;
--
-- ATENCAO: atendimentos que ficaram com mais de um profissional continuam
-- assim. Sem as RPCs, a UI passa a mostrar apenas o primeiro atribuido — os
-- demais permanecem no banco, invisiveis. Revogue-os antes se isso importar:
--   UPDATE appointment_assignments aa SET revoked_at = now()
--   WHERE revoked_at IS NULL
--     AND aa.id NOT IN (
--       SELECT DISTINCT ON (appointment_id) id FROM appointment_assignments
--       WHERE revoked_at IS NULL ORDER BY appointment_id, assigned_at
--     );

DROP FUNCTION IF EXISTS assign_technician(uuid, uuid);
DROP FUNCTION IF EXISTS unassign_technician(uuid, uuid);

DELETE FROM appointment_events
WHERE event_type IN ('technician_added','technician_removed');

ALTER TABLE appointment_events
  DROP CONSTRAINT IF EXISTS appointment_events_event_type_check;

ALTER TABLE appointment_events
  ADD CONSTRAINT appointment_events_event_type_check
  CHECK (event_type IN (
    'scheduled','rescheduled','cancelled','status_changed'
  ));

-- Rollback deliberadamente bloqueado para evitar remover o Owner master por engano.
-- A conta protegida nao deve ser rebaixada ou excluida em operacao normal.
DO $$
BEGIN
  RAISE EXCEPTION '0063_master_owner_account nao possui rollback operacional.'
    USING ERRCODE = '2BP01';
END;
$$;

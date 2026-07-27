-- Rollback: 0050_fix_stock_movements_timestamp_ordering
--
-- Sem perda de dados: so muda o DEFAULT da coluna, linhas existentes nao
-- sao tocadas. Reverter reintroduz o bug de empate de created_at dentro da
-- mesma transacao (ver comentario da migration 0050).

ALTER TABLE stock_movements ALTER COLUMN created_at SET DEFAULT now();

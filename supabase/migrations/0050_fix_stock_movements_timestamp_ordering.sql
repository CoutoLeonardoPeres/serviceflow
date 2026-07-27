-- =============================================================================
-- Migration: 0050_fix_stock_movements_timestamp_ordering
-- Descricao: Corrige stock_movements.created_at para nao empatar dentro da
--            mesma transacao — bug real encontrado no teste 0021 (F3-P5)
-- Depende de: 0042_stock_ledger
-- Rollback: supabase/rollbacks/0050_fix_stock_movements_timestamp_ordering_rollback.sql
--
-- BUG: `now()` no Postgres e fixo por transacao inteira (todas as chamadas a
-- now() dentro da mesma transacao devolvem o mesmo valor) — nao e "agora
-- mesmo", e "quando a transacao comecou". stock_movements.created_at usava
-- DEFAULT now(), entao varios movimentos inseridos na mesma transacao (ex.:
-- um script batch, ou o teste de isolamento 0021) ficam com created_at
-- IDENTICO. Qualquer ORDER BY created_at entre eles fica indeterminado —
-- foi isso que quebrou _sf_resolve_stock_lot() (0047): ao decidir se um
-- numero de serie "esta em estoque" pelo ultimo movimento, a ordem empatada
-- podia devolver o movimento errado.
--
-- Em uso normal (uma RPC por transacao, via cliente Supabase) isso quase
-- nunca aparecia porque cada chamada e sua propria transacao — mas e um bug
-- real, nao um problema so do teste. clock_timestamp() devolve o horario de
-- parede de fato no momento da chamada, sempre crescente mesmo dentro da
-- mesma transacao.
-- =============================================================================

ALTER TABLE stock_movements ALTER COLUMN created_at SET DEFAULT clock_timestamp();

COMMENT ON COLUMN stock_movements.created_at IS
  'clock_timestamp(), nao now() — precisa ser estritamente crescente mesmo dentro da mesma transacao, pois _sf_resolve_stock_lot() (0047) e o extrato dependem de ORDER BY created_at para decidir o ultimo movimento de um lote/serie.';

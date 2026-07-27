-- Rollback: 0049_dre_report
--
-- Sem perda de dados: get_dre_monthly e uma funcao de leitura pura, nao
-- grava nada. Remove-la nao afeta payment_records nem payable_payments.

DROP FUNCTION IF EXISTS get_dre_monthly(integer);

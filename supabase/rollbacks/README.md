# Rollbacks de migration

Cada `NNNN_nome.sql` em `../migrations/` tem um par `NNNN_nome_rollback.sql` aqui.

## Regra de ouro: ordem inversa, sempre

Aplique rollbacks **do maior número para o menor**, sem pular. Rodar fora de
ordem quebra o banco de formas silenciosas.

```
0041 → 0040 → 0039 → 0038 → 0037 → 0036 → …
```

## Por que a ordem importa aqui

Várias migrations usam `CREATE OR REPLACE FUNCTION` sobre funções criadas por
migrations anteriores. Quando isso acontece, o rollback da migration mais nova
precisa **restaurar** a versão antiga da função — não apagá-la.

| Migration | Substituiu funções de | Consequência de rodar fora de ordem |
|---|---|---|
| 0039 | 0036 (`cancel_quotation`, `cancel_work_order`), 0037 (`create_new_quotation_version`), 0038 (`create_return_work_order`) | Rodar o rollback de 0036/0037/0038 antes do de 0039 apaga as funções e deixa 0039 apontando para colunas inexistentes |
| 0041 | 0040 (`seed_default_message_templates`) | Rodar o rollback de 0040 antes do de 0041 deixa a função órfã referenciando `message_templates`, que 0040 remove |
| 0043 | 0009 (`add_work_order_material`) | Rodar o rollback de 0042 antes do de 0043 quebra os FKs de `work_order_materials` para `products`, `warehouses` e `stock_movements` |
| 0044 | — | Rodar o rollback de 0042 antes do de 0044 quebra os FKs de `purchase_orders` para `warehouses` e de `purchase_order_items` para `products` |
| 0045 | 0043 (`add_work_order_material`) | Rodar o rollback de 0043 antes do de 0045 restaura a versão errada da função; rodar o de 0042 antes quebra os FKs de transferências e contagens |
| 0046 | 0045 (`add_work_order_material`) | Só corrige o corpo (bug de log_audit), aridade igual — mas ainda assim precisa rodar depois do rollback de 0046 e antes do de 0045 |
| 0047 | 0042 (`record_stock_entry/exit/adjustment`), 0046 (`add_work_order_material`) | Rodar fora de ordem restaura a versão errada de qualquer uma das 4 funções, ou quebra o FK de `stock_movements.lot_id` para `stock_lots` |
| 0048 | 0044 (`receive_purchase_order`) | Rodar o rollback de 0044 antes do de 0048 quebra os FKs de `payables` para `suppliers` e `purchase_orders`; rodar 0048 fora de ordem deixa `receive_purchase_order` chamando uma função de payables já apagada |
| 0049 | — | `get_dre_monthly` é só leitura (agrega `payment_records`/`payable_payments`); o rollback apaga a função e não depende de ordem em relação a 0048/0013 |
| 0050 | 0042 (coluna `created_at`) | Só muda o `DEFAULT` da coluna — sem FK, sem dependência de ordem com outras migrations |
| 0051 | 0004 (`_sf_set_appointment_meta`, `schedule_appointment`) | Rodar o rollback de 0051 **não** restaura a FK de `appointments.reference_id`, que ela removeu: com agendamento de OS existente a FK não volta. O rollback restaura as duas funções na versão de 0004 |
| 0052 | 0051 (`appointment_events.event_type` CHECK) | Rodar fora de ordem deixa eventos `technician_added`/`technician_removed` violando o CHECK restaurado. O rollback de 0052 apaga esses eventos antes |
| 0053 | 0051 (`schedule_appointment`, `cancel_appointment`), 0052 (`assign_technician`, `unassign_technician`) | **Aridade mudou nas quatro**: `schedule_appointment` 8→9 (`p_professional_id`), `assign_technician`/`unassign_technician` 2→3. O rollback derruba as versões de 0053 mas **não** recria as de 0051/0052 — reaplique-as à mão, senão a agenda fica sem RPC. Rodar o de 0052 antes do de 0053 deixa `assign_technician` órfão apontando para `professional_id`, coluna que 0053 remove |
| 0054 | 0006 (`get_public_quotation`) | Aridade igual; o rollback restaura a versão de 0006, que devolve o orçamento **sem** os itens. A tela pública volta a mostrar só o total |
| 0055 | — | `decide_quotation` é nova; o rollback só a apaga. As decisões já gravadas em `quotation_approvals` permanecem |
| 0056 | 0008 (`convert_approved_quotation_to_work_order`) | Aridade igual. O rollback restaura o corpo completo de 0008 e apaga o trigger, `_sf_quotation_approved_trigger` e `_sf_work_order_from_quotation`. Rodar o de 0008 fora de ordem deixa o trigger apontando para uma função inexistente e **toda aprovação de orçamento passa a falhar** |
| 0057 | 0008 (`transition_work_order`), 0013 (`create_receivable_from_work_order`) | Aridade igual nas duas. O rollback restaura os corpos de 0008/0013, apaga `_sf_work_order_can_transition` e `my_permissions`. Sem `my_permissions` o app cai no modo permissivo (mostra ações que o banco recusa) — é intencional, mas some a filtragem por permissão |
| 0058 | — | Todas as funções são novas; o rollback só as apaga junto com os dois triggers. Independente da 0056: os dois triggers de `quotations` não se cruzam. Chamados já fechados continuam fechados |
| 0059 | — | **Único rollback da série que perde dados**: descarta preços, categorias, histórico e os campos novos de fornecedor e produto. Exporte antes (o arquivo traz os `\copy`). `products.category_id` referencia `material_categories`, então a coluna sai antes da tabela |
| 0060 | — | Função nova; o rollback só a apaga. Os preços já importados e o histórico com origem `spreadsheet` permanecem. Depende das tabelas da 0059, então rode o rollback de 0060 antes do de 0059 |

**Armadilha de aridade:** `CREATE OR REPLACE` com número de parâmetros diferente
**não substitui** — cria uma sobrecarga. As duas versões coexistem e chamadas
com a aridade antiga passam a falhar com `function is not unique`, em runtime.

`add_work_order_material` já mudou de assinatura três vezes: 5→6 em 0043
(`p_product_id`), 6→7 em 0045 (`p_warehouse_id`) e 7→8 em 0047 (`p_lot_code`).
`record_stock_entry`/`record_stock_exit`/`record_stock_adjustment` também
mudaram em 0047 (ganharam `p_lot_code`). `schedule_appointment` mudou 8→9 em
0053 (`p_professional_id`) e `assign_technician`/`unassign_technician` 2→3 —
por isso 0053 derruba explicitamente as assinaturas antigas no fim do arquivo:
duas versões vivas fazem o PostgREST devolver `PGRST203` em vez de executar. Cada migration e cada rollback
correspondente faz `DROP FUNCTION` explícito da versão anterior antes de
criar a nova, com a assinatura completa. **Qualquer migration que mude a
assinatura de uma função precisa do mesmo cuidado** — e o rollback precisa
derrubar a nova antes de restaurar a antiga.

Os scripts afetados trazem um aviso `ATENÇÃO — ordem de rollback` no cabeçalho.

## Rollbacks que perdem dados

Estes removem colunas ou tabelas com dados de produção. Faça dump antes.

| Rollback | O que se perde |
|---|---|
| `0036_cancellations` | Motivos e datas de cancelamento de orçamentos e OS; toda a tabela `quotation_status_history` |
| `0038_work_order_returns` | Vínculo entre OS de retorno e OS original (`parent_work_order_id`); eventos `return_created` |
| `0040_message_templates` | Todos os templates de mensagem e todo o histórico de `communication_logs` |
| `0041_satisfaction_public_survey` | Links de pesquisa emitidos. **Não** apaga as respostas já coletadas em `work_order_satisfaction` |
| `0047_stock_lot_serial_tracking` | Todos os lotes/números de série registrados (`stock_lots`) e o vínculo `lot_id` dos movimentos. Os movimentos em si (`stock_movements`) permanecem — o razão de estoque continua correto |
| `0048_payables` | Todas as contas a pagar e pagamentos registrados (`payables`, `payable_payments`). Os recebimentos de estoque em si (`stock_movements`) permanecem — a mercadoria entrou de fato |

## Rollback com implicação de segurança

**`0039_permissions_and_audit_rollback.sql` reintroduz uma falha de permissão.**

0039 corrigiu `cancel_quotation` e `cancel_work_order`, que antes verificavam
apenas se o usuário pertencia ao tenant — sem checar `quotations.write` /
`work_orders.manage`. Qualquer membro podia cancelar orçamentos e OS.

Reverter 0039 restaura esse comportamento e ainda remove as chamadas
`log_audit` de cancelamentos, novas versões e retornos. Use só em
desenvolvimento, ou em produção como medida emergencial curta, com plano
explícito de reaplicar 0039.

## Como executar

```bash
psql "$SUPABASE_DB_URL" -v ON_ERROR_STOP=1 -f supabase/rollbacks/0041_satisfaction_public_survey_rollback.sql
```

`ON_ERROR_STOP=1` é obrigatório: sem ele, o psql segue após um erro e deixa o
banco num estado intermediário.

## Manutenção

Os rollbacks de 0039 e 0041 contêm cópias literais de funções definidas em
0036–0038 e 0040. **Se aquelas migrations mudarem, estes arquivos precisam ser
regerados** — os cabeçalhos indicam a origem de cada bloco.

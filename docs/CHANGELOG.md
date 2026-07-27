# Changelog

## [Validação RLS real de F3-P5/F4-P1/F4-P2 + bug de created_at] — 2026-07-27

Migrations 0047-0049 aplicadas no Supabase remoto e validadas com
`test/isolation/` 0021-0023 contra o banco real (retomada do runbook de
staging, E8). 21/21 testes passando.

### Corrigido

- **Bug de produção real**: `stock_movements.created_at` usava `DEFAULT
  now()`, que no Postgres é fixo por transação inteira — vários movimentos
  inseridos na mesma transação ficavam com `created_at` idêntico, deixando
  `ORDER BY created_at` indeterminado. Isso quebrava
  `_sf_resolve_stock_lot()` (0047): ao decidir se um número de série "está
  em estoque" pelo último movimento, o empate podia devolver o movimento
  errado — encontrado pelo teste 0021 T8b (reentrada de série após saída,
  rejeitada incorretamente). Corrigido em
  `supabase/migrations/0050_fix_stock_movements_timestamp_ordering.sql`,
  trocando o default para `clock_timestamp()` (sempre crescente, mesmo
  dentro da mesma transação). Em uso normal (uma RPC por transação) o bug
  quase nunca aparecia — mas é real, não só do teste.

## [F4-P2 — DRE simples em regime de caixa] — 2026-07-27

ADR-026 decidido e implementado: relatório de resultado mensal a partir do
que já existe (`payment_records`, `payable_payments`), sem esperar contas
bancárias nem plano de contas.

### Adicionado

- `docs/DECISIONS.md`: ADR-026 — receita = `payment_records` pagos,
  despesa = `payable_payments` pagos, por mês; regime de caixa (não
  competência); meses sem pagamento não aparecem (sem zero-preenchimento).
- `supabase/migrations/0049_dre_report.sql`: `get_dre_monthly(p_year)` —
  função de leitura pura, sem tabela nova, exige `financials.read`.
- `supabase/rollbacks/0049_dre_report_rollback.sql` (sem perda de dados —
  só remove a função) + `test/isolation/0023_dre_report_test.sql` (6 casos:
  agregação correta por mês, resultado = receita − despesa, ano sem
  movimento não gera linha vazia, ano obrigatório, permissão
  `financials.read`, isolamento entre tenants).
- Flutter: `DreMonth`/`dreMonthFromRow`;
  `FinancialRepository.getDreMonthly`; `DreScreen` com seletor de ano,
  totais anuais e cartão por mês; nova entrada "DRE" na navegação
  (reaproveita `TenantFeature.financials`).
- `test/financials/dre_month_domain_test.dart`.

### Limitação conhecida (aceita, não é bug)

- Regime de caixa, não competência: uma venda fechada em dezembro e paga
  em janeiro aparece em janeiro. Sem CMV por venda, sem plano de contas,
  sem centro de custo — ADR-026 documenta isso como corte deliberado.

### Pendente

- `supabase db push` da migration 0049 e execução de
  `test/isolation/0023` contra o banco real.
- `flutter analyze`/`flutter test` das mudanças acima (sem Flutter SDK no
  ambiente de análise).

## [F4-P1 — Contas a pagar automáticas no recebimento] — 2026-07-27

ADR-025 decidido e implementado: fecha a lacuna que a migration 0044 (F3-P3)
já deixava documentada — o pedido de compra recebido não gerava conta a
pagar, o compromisso financeiro ficava fora do sistema. Abre a fase F4.

### Adicionado

- `docs/DECISIONS.md`: ADR-025 — `payables` nasce automaticamente dentro
  da transação de `receive_purchase_order` (cada recebimento soma o valor
  recebido); baixa manual simples, espelhando `receivables`/`payment_records`
  (E8), sem introduzir `financial_accounts` nesta entrega.
- `supabase/migrations/0048_payables.sql`: tabelas `payables` (única por
  `purchase_order_id`, upsert somando valor a cada recebimento parcial) e
  `payable_payments`; `_sf_upsert_payable_on_receipt` (chamado só de dentro
  de `receive_purchase_order`); `register_payable_payment` (baixa manual,
  reaproveita as permissões `financials.read`/`financials.write` já
  existentes — nenhuma permissão nova); `list_payables`.
- `supabase/rollbacks/0048_payables_rollback.sql` (restaura
  `receive_purchase_order` sem o upsert de payables) +
  `test/isolation/0022_payables_test.sql` (11 casos: criação automática,
  soma em recebimentos parciais sucessivos, baixa parcial/total, pagamento
  acima do saldo bloqueado, payable paga rejeita novo pagamento, sem
  escrita direta nas tabelas, permissão `financials.write`, isolamento
  entre tenants, auditoria).
- Flutter: `Payable`/`payableFromRow` (reaproveita `ReceivableStatus` —
  mesmo vocabulário aberto/parcial/pago/cancelado, sem duplicar enum);
  `FinancialRepository.listPayables`/`registerPayablePayment`;
  `PayablesScreen` com baixa manual, nova entrada "A Pagar" na navegação
  (reaproveita `TenantFeature.financials`, sem trava de plano nova).
- `test/financials/payable_domain_test.dart`: `payableFromRow`,
  `Payable.isOverdue`.

### Fora de escopo (documentado, não é bug)

- `financial_accounts` (contas bancárias/caixa), `bank_reconciliation`,
  `chart_of_accounts`, `cost_centers`, `financial_transactions` como
  livro-razão único, DRE — ficam para as próximas entregas de F4.
- `receivables`/`payment_records` (E8) continuam exatamente como estão,
  sem migração de dados.

### Pendente

- `supabase db push` da migration 0048 e execução de
  `test/isolation/0022` contra o banco real.
- `flutter analyze`/`flutter test` das mudanças acima (sem Flutter SDK no
  ambiente de análise).

## [F3-P5 — Rastreio opcional de lote/série] — 2026-07-27

ADR-024 decidido e implementado: rastreabilidade opcional por produto,
sem redesenhar o custo médio ponderado (ADR-020). Fecha a fase F3.

### Adicionado

- `docs/DECISIONS.md`: ADR-024 — rastreio opcional (`none|lot|serial`),
  obrigatório só para o produto que o dono escolher marcar, sem controle
  de validade nesta entrega.
- `supabase/migrations/0047_stock_lot_serial_tracking.sql`: coluna
  `products.tracking_type`; tabela `stock_lots` (identidade, único
  case-insensitive por produto); `stock_movements.lot_id`;
  `_sf_resolve_stock_lot` (find-or-create na entrada, must-exist na
  saída, serial trava quantidade=1 e uma posse por vez);
  `record_stock_entry`/`record_stock_exit`/`record_stock_adjustment`/
  `add_work_order_material` ganham `p_lot_code`; `list_stock_lots` e
  `get_lot_history` para consulta.
- `supabase/rollbacks/0047_stock_lot_serial_tracking_rollback.sql` +
  `test/isolation/0021_stock_lot_serial_test.sql` (12 casos: obrigatoriedade
  na entrada/saída, reuso de código por case-insensitive, serial
  rejeitando quantidade≠1 e reentrada antes da saída, `get_lot_history`,
  isolamento RLS entre tenants).
- Flutter: `Product.trackingType` (`ProductTrackingType` enum);
  `StockRepository`/`WorkOrderRepository` ganham `lotCode`/`p_lot_code`
  em entrada, saída, ajuste e material de OS; dropdown de rastreio no
  cadastro de produto; campo condicional de lote/série nos diálogos de
  movimento de estoque e no material da OS (aparece só quando o produto
  selecionado tem `trackingType != none`); chip de lote no extrato de
  movimentos, abrindo histórico via `get_lot_history`.
- `test/stock/stock_domain_test.dart`: testes de
  `productTrackingTypeFromString`, `tracking_type` em `productFromRow`,
  `lot_id`/`lot_code` em `stockMovementFromRow`.

### Fora de escopo (documentado, não é bug)

- `transfer_stock` e `stock_counts` não recebem `lot_id` nesta entrega —
  preservam a conservação exata de valor (ADR-020) e o ajuste agregado,
  respectivamente.

### Pendente

- `supabase db push` da migration 0047 e execução de `test/isolation/0021`
  contra o banco real.
- `flutter analyze`/`flutter test` das mudanças acima (sem Flutter SDK no
  ambiente de análise).

## [Release check + security preflight corrigidos] — 2026-07-27

Primeira execução real de `scripts/release_check.sh` e
`scripts/security_preflight.sh`, achou 3 bugs — o mais sério deixava a
varredura de segredos rodar em falso.

### Corrigido

- `scripts/build_staging.sh`: não criava `dist/` antes do `zip`, falhava
  com "No such file or directory".
- `scripts/release_check.sh`: `flutter analyze` sai com código != 0 para
  qualquer issue, mesmo só "info" cosmético (API deprecated) — sob `set -e`
  isso matava o script inteiro sem aviso. Agora só bloqueia em erro real.
- **`scripts/security_preflight.sh` (achado mais sério)**: o passo de busca
  de segredos usava `rg` (ripgrep), que não está instalado por padrão —
  `if rg ...` com comando inexistente falha silenciosamente e o `if` trata
  isso como "não achou nada", pulando a varredura inteira e ainda reportando
  "OK". Trocado por `grep -r` (sem dependência nova). Em seguida, dois ajustes
  de precisão: (1) o regex original casava pelo *nome* da variável
  `SUPABASE_SERVICE_ROLE_KEY`, dando falso positivo em docs/scripts que
  legitimamente citam o nome sem conter valor real; trocado para casar pelo
  *formato* de uma chave (JWT de três blocos ou prefixo `sb_secret_`). (2)
  isso por si só também dava falso positivo na `anon key` (que é pública por
  design, protegida por RLS) — agora decodifica o payload do JWT e só falha
  se o claim `role` for `service_role`.

## [Cadastro de categorias e prioridades de chamado] — 2026-07-27

Tabelas `service_categories`/`service_priorities` já existiam desde 0003;
faltava UI de cadastro (só havia leitura para os dropdowns do formulário de
chamado).

### Adicionado

- `ServiceRequestRepository`: `listAllCategories`, `createCategory`,
  `updateCategory`, `listAllPriorities`, `createPriority`, `updatePriority`.
  Sem `delete*` — as tabelas não têm policy de DELETE (proposital); "excluir"
  na UI é `UPDATE is_active = false`.
- `ServiceCategoryScreen`, `ServicePriorityScreen` — CRUD em Configurações →
  Chamados, rotas `/configuracoes/categorias-chamado` e
  `/configuracoes/prioridades-chamado`.
- Providers `serviceCategoriesAllProvider`/`servicePrioritiesAllProvider`
  (mostram inativos também, diferente dos providers de dropdown existentes).

## [Validação RLS em banco real] — 2026-07-27

Primeira execução de migrations e testes de isolamento contra um Supabase
real (`pkbluscdssiiumrppmwa`), depois de meses acumulando migrations nunca
verificadas. Resultado: 18/18 testes automatizados passando, após corrigir 6
bugs — 5 nos scripts/testes, 1 em código de produção.

### Corrigido

- `scripts/create_test_users.sh`: `declare -A` não funciona no bash 3.2 do
  macOS — trocado por arrays indexados paralelos. Um `grep|head|cut` sob
  `pipefail` também matava o script em silêncio quando a chave era inválida
  (grep sem match = exit 1 = script inteiro aborta antes do aviso); trocado
  por `|| true`.
- `scripts/apply_test_uuids.sh`: `:'VAR'` do psql não interpola de forma
  confiável dentro de `DO $$...$$` (o rastreador de aspas do psql se
  desalinha com o número de aspas simples do corpo PL/pgSQL). Substituição
  agora troca `:'VAR'` por literal diretamente no corpo, não só na linha
  `\set`.
- `scripts/run_isolation_tests.sh`: relatório só capturava `NOTICE:`/`ERROR:`,
  escondendo falhas de conexão (`FATAL:`/`psql: error:`).
- `test/isolation/*.sql` (18 arquivos): `WHEN SQLSTATE 'P0001' AND SQLERRM =
  ...` não é sintaxe válida de PL/pgSQL (`WHEN` só aceita `OR` entre
  condições) — trocado por `WHEN SQLSTATE 'P0001' THEN IF SQLERRM = ... THEN
  ... ELSE RAISE; END IF;`.
- `test/isolation/0002,0003,0004,0005,0007–0016`: setup inserindo dados
  direto sem simular o usuário dono do tenant — o trigger de
  auto-preenchimento de `tenant_id` (`current_tenant_id()`) corretamente
  rejeitava por design (`tenant_id` nunca é aceito cegamente do cliente).
  Adicionado `SET LOCAL role = authenticated` + `set_config` do usuário certo
  antes de cada INSERT de setup.
- `test/isolation/0002` T4, `0003` T5: RLS em UPDATE não lança exceção
  quando a policy filtra a linha, só zera `ROW_COUNT` — testes esperavam
  `insufficient_privilege`. Trocado por `GET DIAGNOSTICS ... ROW_COUNT`.
- `test/isolation/0014` T2: `cancel_quotation` levanta `P0001` genérico, não
  `check_violation` — corrigido, com cuidado extra para não engolir o
  próprio `RAISE EXCEPTION 'FALHOU T2...'` do teste (mesmo código de erro).
- `test/isolation/0016`: `set_config('request.jwt.claims', ...)` é
  transaction-local — trocar `SET LOCAL role = anon` sozinho não limpa o
  claim JWT do usuário simulado anteriormente. T14 lia dados reais porque a
  sessão "anon" ainda carregava a identidade do técnico. Adicionado
  `set_config('request.jwt.claims', 'null', true)` antes de cada simulação
  de `anon`.
- **`supabase/migrations/0046_fix_material_audit_metadata.sql` (produção)**:
  `add_work_order_material` chamava `log_audit(..., jsonb_de_detalhes)` no
  6º argumento (`p_after_data`) em vez do 7º (`p_metadata`) — o log de
  auditoria gravava, mas com os detalhes (`from_stock`, `warehouse_id` etc.)
  no campo errado, invisíveis para qualquer consulta que filtre por
  `metadata`. `CREATE OR REPLACE` sem mudança de aridade, com rollback
  correspondente.

## [F3-P4 — Transferências, inventário cíclico e multi-depósito na OS] — 2026-07-26

### Adicionado

- `supabase/migrations/0045_transfers_counts_multi_warehouse.sql`:
  - `stock_transfers` / `stock_transfer_items` — transferência entre depósitos.
  - `stock_counts` / `stock_count_items` — sessão de inventário cíclico.
  - RPCs `transfer_stock`, `create_stock_count`, `set_stock_count_quantity`,
    `apply_stock_count`, `cancel_stock_count`, `list_stock_count_items`.
  - `add_work_order_material` ganha `p_warehouse_id` opcional.
- `supabase/rollbacks/0045_transfers_counts_multi_warehouse_rollback.sql`.
- `test/isolation/0020_transfers_counts_test.sql` — 14 casos.
- Flutter: `StockTransfer`, `StockCount`, `StockCountItem`, métodos no
  repositório, telas de transferência e inventário, seletor de depósito no
  material da OS.
- Rotas `/estoque/transferencias` e `/estoque/inventario`.
- `test/stock/stock_transfer_count_test.dart` (20 casos).

### Conservação de valor na transferência

**A transferência não usa `record_stock_exit` + `record_stock_entry`.** Aqueles
RPCs recalculam custo a partir de `unit_cost`, e `round(qtd × round(V/qtd)) ≠ V`
no caso geral — cada transferência perderia ou criaria centavos, e o valor total
do estoque derivaria com o tempo. O valor V é calculado uma vez na origem e
gravado idêntico no destino.

Os casos T3 e T4 de 0020 usam 3 unidades a R$ 33,33 (valor 9999, não divisível
por 3) justamente para pegar esse erro: verificam que a soma dos valores dos
dois depósitos continua exatamente 9999 depois da transferência, e que zerar a
origem leva o valor integral sem resíduo.

### Ordem de trava para evitar deadlock

Transferências simultâneas A→B e B→A poderiam travar uma à outra. As linhas de
saldo são travadas sempre na ordem crescente de `warehouse_id`, o que garante
ordem global consistente.

### Inventário como sessão persistida

Contagem é uma sessão (`open → applied/cancelled`), não ajuste em lote direto: a
contagem real se estende no tempo, e o registro de quem contou o quê é a
justificativa auditável do ajuste. `apply_stock_count` reutiliza
`record_stock_adjustment` — um ajuste por item divergente, sem caminho paralelo
de escrita. O saldo é **relido na aplicação**, não usa o snapshot da abertura,
porque pode ter mudado no intervalo.

### Nota técnica — aridade, de novo

`add_work_order_material` foi de 6 para 7 parâmetros. Mesmo cuidado de 0043:
`DROP FUNCTION` explícito antes de recriar, senão as duas versões coexistem e
chamadas com 6 argumentos falham com `function is not unique`. É a segunda vez
que essa função muda de assinatura — o padrão está no README de rollbacks.

---

## [F3-P3 — Fornecedores e pedidos de compra] — 2026-07-26

### Adicionado

- `supabase/migrations/0044_suppliers_purchase_orders.sql`:
  - `suppliers` (tabela própria — a unificação de parceiros é F5, e acoplar
    agora amarraria módulos que ainda vão mudar).
  - `purchase_orders` com ciclo `draft → sent → partially_received → received`
    e `draft/sent → cancelled`. Numeração por tenant via `next_sequence`.
  - `purchase_order_items` com `quantity_ordered` / `quantity_received` e
    CHECK impedindo receber acima do pedido.
  - RPCs `create_purchase_order`, `send_purchase_order`,
    `receive_purchase_order`, `cancel_purchase_order`,
    `list_purchase_order_items`.
  - Permissões `purchases.read`, `purchases.write`, `purchases.receive`
    (técnico recebe mercadoria mas não emite pedido), com backfill de grants.
- `supabase/rollbacks/0044_suppliers_purchase_orders_rollback.sql`.
- `test/isolation/0019_purchase_orders_test.sql` — 17 casos.
- Flutter `lib/features/purchases/`: domínio, repositório, providers e telas de
  fornecedores, lista de pedidos, novo pedido e detalhe com recebimento.
- Rotas `/compras`, `/compras/novo`, `/compras/fornecedores`,
  `/compras/pedido/:id` e item "Compras" na navegação.
- `test/purchases/purchase_order_test.dart` (18 casos).

### Regras que valem registro

- **O pedido não movimenta estoque.** Só o recebimento gera entrada, e com o
  custo real da nota — não o cotado. Se o preço mudou entre pedido e entrega, o
  custo médio reflete o que foi pago. O teste T7 de 0019 verifica isso.
- **Recebimento parcial mantém o pedido aberto**, com a pendência por item.
- **Pedido com recebimento parcial não pode ser cancelado.** A mercadoria já
  entrou; cancelar apagaria o rastro de algo que existe fisicamente. Divergência
  se corrige por ajuste de inventário, que exige `stock.adjust` e motivo.
- **Receber a mais que o pedido é bloqueado** — é erro de conferência, e deixar
  passar mascararia divergência com o fornecedor.

### Fronteira com o financeiro

O pedido registra custo mas **não gera conta a pagar** — `payables` não existe
(previsto para F4). Ligar compra ao contas a pagar é escopo de F4.

### Acoplamento de permissão a observar

`receive_purchase_order` chama `record_stock_entry`, que checa `stock.write` por
conta própria. Receber exige, na prática, `purchases.receive` **e**
`stock.write`. Todos os papéis com `purchases.receive` já têm `stock.write` de
0042; se um papel novo ganhar só a primeira, o recebimento falha com mensagem de
estoque que não explica a causa. Documentado na própria migration.

---

## [F3-P2 — Consumo da OS gerando movimento de estoque] — 2026-07-26

Fecha o ADR-016, aberto desde a F1: o material lançado na OS agora baixa o
estoque de verdade.

### Decisão de produto

Vínculo com o catálogo é **opcional**. O técnico escolhe um produto (baixa o
saldo, custo vem do médio) ou digita texto livre (só registra custo). Travar o
lançamento quando o cadastro está incompleto ou o saldo diverge penalizaria
quem está em campo, sem acesso ao cadastro. `from_stock` permite medir quanto
do consumo ficou fora do controle de estoque.

### Adicionado

- `supabase/migrations/0043_work_order_stock_consumption.sql`:
  - `work_order_materials` ganha `product_id`, `warehouse_id` e
    `stock_movement_id` (todos nulos — expand-and-contract).
  - `add_work_order_material` reescrita com `p_product_id` opcional. Com
    produto que controla saldo, chama `record_stock_exit` e **sobrescreve o
    custo digitado pelo custo médio vigente** — o custo do material é o que ele
    custou à empresa, não o que o técnico estimou.
  - `list_work_order_materials` devolve `from_stock` por lançamento.
- `supabase/rollbacks/0043_work_order_stock_consumption_rollback.sql`.
- `test/isolation/0018_work_order_stock_consumption_test.sql` — 12 casos,
  incluindo a prova de que saldo insuficiente **aborta o lançamento inteiro**:
  sem material órfão, sem alteração no total da OS, sem mexer no saldo.
- `WorkOrderMaterial` + `WorkOrderMaterialResult`, `listMaterials` no
  repositório, seletor de produto no formulário de material, e
  `test/work_orders/work_order_material_test.dart` (10 casos).

### Nota técnica — armadilha de aridade

`add_work_order_material` passou de 5 para 6 parâmetros. `CREATE OR REPLACE`
com aridade diferente **não substitui**: cria uma sobrecarga, e toda chamada
com 5 argumentos passa a falhar em runtime com `function is not unique`. A
migration e o rollback fazem `DROP FUNCTION` explícito antes de criar. O caso
está documentado em `supabase/rollbacks/README.md` para as próximas mudanças de
assinatura.

### Nota — ordem de rollback

O rollback de 0043 precisa rodar **antes** do de 0042: as colunas novas
referenciam `products`, `warehouses` e `stock_movements`. Movimentos já gerados
permanecem no razão após o rollback — a baixa aconteceu de fato, e
`stock_movements` é append-only.

---

## [F3-P1 — Núcleo do razão de estoque] — 2026-07-26

Primeira entrega da F3. Estabelece o razão de estoque sobre o qual compras,
consumo de OS e inventário serão construídos.

### Decisões

- **ADR-020 registrado — custo médio ponderado móvel.** Descartadas: última
  compra (não aceita para inventário fiscal no Brasil) e PEPS/FIFO (exigiria
  camadas de custo por entrada; complexidade não justificada para material de
  FSM). Consequências e caminho de migração futura em `docs/DECISIONS.md`.
- **Estoque liberado em todos os planos** (`TenantFeature.stock` em starter,
  professional, business e enterprise).

### Adicionado

- `supabase/migrations/0042_stock_ledger.sql`:
  - `products` (sku único por tenant, unidade, `track_stock`, `min_quantity`),
    `warehouses` (um padrão por tenant via índice parcial único).
  - `stock_movements` **append-only** — sem policy de UPDATE/DELETE. `quantity`
    sempre positiva; a direção vem de `kind`. Cada lançamento grava o saldo
    resultante (`quantity_after`, `value_after_cents`).
  - `stock_balances` derivado, guardando `quantity` + **`total_value_cents`**.
    O custo médio é derivado por `stock_average_unit_cost_cents()`, não
    armazenado — guardar o médio arredondado e recalculá-lo a cada entrada
    acumularia erro de arredondamento.
  - RPCs `record_stock_entry`, `record_stock_exit`, `record_stock_adjustment`,
    `list_stock_balances`. Todos travam a linha de saldo com `FOR UPDATE` antes
    de ler; sem isso, duas saídas simultâneas passariam ambas pela checagem e
    deixariam o saldo negativo.
  - Permissões `stock.read`, `stock.write`, `stock.adjust` (ajuste é mais
    restrito: sobrepõe o cálculo do sistema), com grants para os papéis
    existentes.
- `supabase/rollbacks/0042_stock_ledger_rollback.sql`.
- `test/isolation/0017_stock_ledger_test.sql` — 16 casos: custo médio conferido
  contra cálculo manual, saldo negativo bloqueado, resíduo de arredondamento em
  saldo zerado, imutabilidade dos movimentos, `stock_balances` não gravável
  direto, técnico sem `stock.adjust`, viewer sem `stock.write`, isolamento entre
  tenants e auditoria.
- Flutter `lib/features/stock/`: domínio (`Product`, `Warehouse`,
  `StockMovement`, `StockBalance`), `StockRepository`, providers, e telas de
  saldos, extrato e catálogo, com diálogos de entrada/saída/ajuste.
- Rotas `/estoque`, `/estoque/produtos`, `/estoque/movimentos/:productId` e
  item "Estoque" na navegação.
- `test/stock/stock_domain_test.dart` (24 casos) e
  `test/stock/stock_list_screen_test.dart` (7 casos de widget).

### Corrigido

- `docs/DATA_MODEL.md` afirmava que `work_order_materials` tinha `product_id`.
  **A coluna nunca foi implementada** em 0009. Documento corrigido; a ligação
  com o catálogo é escopo do F3-P2 (ADR-016).
- `.gitignore` — adicionado `.fuse_hidden*`, placeholders que o mount FUSE deixa
  ao reescrever arquivo aberto e que apareciam como untracked.

### Nota sobre permissões

O grant original de `tenant_owner` em 0001 é um cross join sem filtro,
executado uma única vez. **Permissões criadas em migrations posteriores não
chegam sozinhas aos papéis existentes** — 0042 faz backfill explícito. Qualquer
migration futura que adicione permissão precisa fazer o mesmo.

---

## [Cobertura — Testes de isolamento RLS para as tabelas do F2] — 2026-07-26

A suíte de isolamento parou de acompanhar as migrations em 0014. Nenhuma das
quatro tabelas criadas no F2 tinha teste de RLS. Como a validação RLS é o
critério bloqueador de aceite do MVP, rodar a suíte assim daria falsa segurança.

### Adicionado

- `test/isolation/0014_cancellations_history_test.sql` — 7 casos sobre
  `quotation_status_history` (0036) e as permissões de 0039.
  **T3 e T4 são testes de regressão da falha corrigida em 0039**: verificam que
  um técnico, que tem `work_orders.execute` mas não `quotations.write` nem
  `work_orders.manage`, não consegue cancelar orçamento nem OS. Antes de 0039
  isso era permitido. Se alguém reverter 0039, estes casos falham.
- `test/isolation/0015_communications_test.sql` — 9 casos sobre
  `message_templates` e `communication_logs` (0040): isolamento entre tenants,
  exigência de `customers.write` para escrita, leitura permitida ao viewer, e
  imutabilidade dos logs (nem o próprio owner altera ou apaga).
- `test/isolation/0016_satisfaction_public_link_test.sql` — 16 casos sobre a
  pesquisa pública (0041), o único caminho de escrita anônima do F2:
  token em claro nunca persistido (só o SHA-256), contexto público sem dado de
  cliente (verificado por chave e por conteúdo textual), token inválido /
  expirado / revogado rejeitado na leitura e na escrita, novo link revogando o
  anterior, upsert em vez de duplicata, `anon` sem leitura direta da tabela, e
  auditoria de emissão e resposta.

### Corrigido

- `scripts/apply_test_uuids.sh` — a lista de arquivos era fixa
  (`000{2,3,4,5,7,8,9}` e `001{0,1,2,3}`), então testes novos ficavam de fora
  **silenciosamente**: seriam criados, não gerados, não executados, e o runner
  ainda reportaria sucesso. Trocado por glob numérico com lista explícita de
  exclusões (só os que exigem execução manual). Esta era a causa raiz da
  defasagem, não apenas os três testes faltantes.
- `scripts/run_isolation_tests.sh` — cabeçalho dizia "12 testes" fixo.

### Nota

Nenhum teste foi executado — o ambiente de análise não tem PostgreSQL. A
execução real contra o banco continua pendente e é bloqueador do MVP.

---

## [Correção — Rollbacks de migration ausentes] — 2026-07-26

Lacuna encontrada ao criar o rollback de 0041: as migrations 0036 a 0040 tinham
sido escritas sem par de rollback, quebrando a cobertura 1:1 que ia de 0001 a
0035.

### Adicionado

- `supabase/rollbacks/0036_cancellations_rollback.sql`
- `supabase/rollbacks/0037_quotation_versioning_rollback.sql`
- `supabase/rollbacks/0038_work_order_returns_rollback.sql`
- `supabase/rollbacks/0039_permissions_and_audit_rollback.sql`
- `supabase/rollbacks/0040_message_templates_rollback.sql`
- `supabase/rollbacks/README.md` — ordem inversa obrigatória, quais rollbacks
  perdem dados, e a implicação de segurança de reverter 0039.

### Corrigido

- `supabase/rollbacks/0041_satisfaction_public_survey_rollback.sql` — a versão
  inicial apenas removia o que 0041 criou, mas 0041 havia substituído
  `seed_default_message_templates`. Sem restaurar a versão de 0040, o rollback
  deixaria a função com o template de pesquisa apontando para uma feature
  removida. Agora restaura a definição original e apaga o template do backfill.

### Notas de execução

- **Ordem inversa é obrigatória.** 0039 substituiu quatro funções de 0036/0037/
  0038, então seu rollback precisa *restaurar* essas versões, não removê-las.
  Rodar os rollbacks fora de ordem deixa funções órfãs referenciando colunas já
  removidas. Avisos no cabeçalho de cada script afetado.
- **Reverter 0039 reintroduz uma falha de permissão.** Antes de 0039,
  `cancel_quotation` e `cancel_work_order` checavam apenas a associação ao
  tenant, não a permissão específica. O rollback restaura esse comportamento e
  remove as chamadas `log_audit`. Documentado no topo do script e no README.
- Perdem dados: 0036 (motivos de cancelamento + `quotation_status_history`),
  0038 (vínculo de retorno), 0040 (templates + `communication_logs`).
- Nenhum rollback foi executado — ambiente de análise sem PostgreSQL.

---

## [F2-P5 — Pesquisa de satisfação respondida pelo cliente] — 2026-07-26

Fecha o F2. Antes desta entrega a nota de satisfação era digitada pelo técnico
na tela da OS — um registro interno, não uma pesquisa. Agora o próprio cliente
responde, por link público.

### Adicionado

- `supabase/migrations/0041_satisfaction_public_survey.sql`:
  - Tabela `satisfaction_public_links` (token_hash SHA-256, `expires_at`,
    `revoked_at`, `use_count`, `last_access_at`, `responded_at`). RLS com SELECT
    restrito ao tenant; nenhuma policy de escrita — toda mutação passa por RPC.
  - `create_satisfaction_public_link(work_order_id, expires_at)` — exige
    `work_orders.execute` ou `.manage`, só aceita OS com status `done`, expira em
    30 dias por padrão e revoga o link anterior da mesma OS. Retorna o token em
    claro uma única vez; o banco guarda apenas o hash.
  - `revoke_satisfaction_public_link(work_order_id)`.
  - `get_public_satisfaction_context(token)` — **anônimo**. Devolve apenas número
    da OS, título do serviço, nome da empresa e se já houve resposta.
  - `submit_public_satisfaction(token, rating, contact_name, comment)` —
    **anônimo**. Tenant e OS derivados do token, nunca do cliente. Grava em
    `work_order_satisfaction`, registra evento na OS e chama `log_audit`.
  - Template padrão "Pesquisa de satisfacao" + backfill para tenants que já
    haviam rodado `seed_default_message_templates`.
- `supabase/rollbacks/0041_satisfaction_public_survey_rollback.sql`.
- `lib/features/work_orders/domain/satisfaction_public_context.dart` —
  `SatisfactionPublicContext` + `satisfactionRatingLabel`.
- `lib/features/work_orders/presentation/satisfaction_public_screen.dart` —
  seletor de 1 a 5 estrelas com `Semantics`, nome e comentário opcionais, painel
  de agradecimento após envio.
- Rota `/pesquisa/:token`, liberada no redirect do router (sem auth, sem bloqueio
  por plano).
- `WorkOrderRepository`: `createSatisfactionPublicLink`,
  `revokeSatisfactionPublicLink`, `getPublicSatisfactionContext`,
  `submitPublicSatisfaction`.
- Botão "Enviar pesquisa" na OS concluída — gera o link e abre o painel de envio
  com `{{link}}` já preenchido.
- `showSendMessageSheet(context, messageContext)` em `send_message_panel.dart`,
  para abrir o painel sem depender do botão.
- Testes: `test/work_orders/satisfaction_public_context_test.dart` (13 casos) e
  `test/work_orders/satisfaction_public_screen_test.dart` (7 casos de widget,
  com repositório falso — nenhum teste toca Supabase).

### Segurança

- Segundo endpoint anônimo de escrita do sistema. Inventário completo e
  divergências registradas em `docs/THREAT_MODEL.md` § "Endpoints anônimos".
- Mitigações aplicadas: token opaco de 32 bytes, armazenado só como SHA-256;
  expiração obrigatória; revogação; escopo de uma única OS; dados mínimos na
  leitura pública.
- **Não aplicado (decisão de produto):** rate limit por IP — exigiria Edge
  Function. Resposta não é única: o cliente pode corrigir a nota enquanto o link
  valer. Risco residual e recomendação de reavaliação antes do GA registrados no
  THREAT_MODEL.

---

## [F2-P4 — Testes E2E e widget] — 2026-07-26

### Adicionado

- `test/communications/message_template_test.dart`:
  - `MessageChannel.fromString` e `.label` para todos os valores.
  - `MessageTemplate.resolveBody`: substituição completa, variáveis ausentes preservadas, mapa vazio.
  - `MessageTemplate.resolveSubject`: com variáveis e quando `subject` é null.
  - `TemplateVars.all` e `TemplateVars.label` para todas as chaves.
  - `messageTemplateFromRow`: row completo e `is_active` null assume `true`.
- `test/settings/audit_log_test.dart`:
  - `actionLabel` para ações de orçamento, OS, cliente e financeiro; ação desconhecida retorna raw.
  - `entityLabel` para todas as entidades conhecidas; desconhecida retorna raw.
  - `auditLogEventFromRow`: row completo e row sem campos opcionais.
- `test/quotations/quotation_version_test.dart`:
  - `QuotationVersion.label` com `isCurrent=true` (sufixo "(atual)") e `isCurrent=false`.
  - `quotationVersionFromRow` com `is_current` verdadeiro e falso.
  - `QuotationStatusEvent` via `quotationStatusEventFromRow` com e sem `notes`.

### Corrigido

Erros de compilação em código de produção de F2-P2/F2-P3, revelados ao executar a suíte:

- `lib/features/communications/data/communication_repository.dart` — `listTemplates` e `listLogs`
  aplicavam `.eq()` **depois** de `.order()/.limit()`, que retornam `PostgrestTransformBuilder`
  (sem `.eq()`). Filtros movidos para antes dos transforms; casts `as dynamic` removidos.
- `lib/features/settings/presentation/audit_log_screen.dart` e
  `lib/features/communications/presentation/message_template_screen.dart` — usavam
  `NeomorphicCard`, widget inexistente. Trocado por `NeomorphicPanel` (API idêntica).
- `lib/features/settings/presentation/audit_log_screen.dart` — lia `AppError.message`;
  o campo correto é `AppError.userMessage` (nomeado assim para não vazar detalhe técnico).
- `lib/features/communications/domain/message_template.dart` — `'Valor (R$)'` era interpretado
  como interpolação de string. Convertido para raw string (`r'...'`).

### Alterado

- `test/work_orders/work_order_detail_screen_test.dart`:
  - `setUpAll` com `initializeDateFormatting('pt_BR')` — o painel de eventos formata datas com
    `DateFormat` e lançava `LocaleDataException` sem essa inicialização.
  - Todos os 6 testes existentes ampliados com overrides para `workOrderEventsProvider` e
    `customerDetailProvider` (providers adicionados à tela em F2-P1/F2-P3 que estavam ausentes).
  - 4 novos `testWidgets` cobrindo funcionalidades F2-P1:
    - Botão "Criar retorno" visível para OS com `status=done`.
    - Painel de cancelamento exibe motivo e oculta "Criar retorno" para OS cancelada.
    - Chip "Retorno" visível para OS com `parentWorkOrderId != null`.
    - Painel de histórico exibe eventos com label e notas.
- `test/quotations/quotation_detail_screen_test.dart`:
  - Os 2 testes existentes ampliados com overrides para `quotationVersionsProvider`,
    `quotationStatusHistoryProvider` e `customerDetailProvider`.
  - 4 novos `testWidgets` cobrindo funcionalidades F2-P1:
    - Botão "Cancelar orçamento" visível para status `draft`.
    - Botão "Cancelar orçamento" ausente para status `approved`.
    - Botão "Cancelar orçamento" ausente para status `cancelled`.
    - Painel "Versões do orçamento" exibe versões com label correto (incluindo sufixo "(atual)").

---

## [F2-P3 — Templates de mensagem + Outbox + Registro de comunicação] — 2026-07-25

### Adicionado

- `supabase/migrations/0040_message_templates.sql`:
  - Tabela `message_templates` (canal, nome, assunto, corpo com variáveis `{{...}}`, is_active, RLS).
  - Tabela `communication_logs` (cliente, canal, direção, status, preview, entidade relacionada, RLS imutável).
  - RPC `log_communication(...)` SECURITY DEFINER: valida tenant + `customers.write`, registra
    comunicação e emite `log_audit('communication.sent')`.
  - Função `seed_default_message_templates(p_tenant_id)`: insere 5 templates padrão (confirmação
    de agendamento, orçamento enviado, OS concluída, cobrança pendente, e-mail de orçamento). Idempotente.
- `lib/features/communications/domain/message_template.dart`:
  - `MessageTemplate` com `resolveBody/resolveSubject` (substituição de variáveis `{{key}}`).
  - `MessageChannel` enum (whatsapp, email, generic, phone).
  - `TemplateVars` com constantes e `label()`.
- `lib/features/communications/domain/communication_log.dart`: `CommunicationLog` com `statusLabel`.
- `lib/features/communications/data/communication_repository.dart`:
  - CRUD de templates: `listTemplates`, `createTemplate`, `updateTemplate`, `deleteTemplate`.
  - `seedDefaultTemplates()`, `listLogs()`, `logCommunication()`.
- `lib/features/communications/application/communication_notifier.dart`:
  - `communicationRepositoryProvider`, `messageTemplatesProvider`,
    `messageTemplatesByChannelProvider`, `customerCommunicationLogsProvider`,
    `entityCommunicationLogsProvider`.
- `lib/features/communications/presentation/send_message_panel.dart`:
  - `MessageContext` — dados do cliente + contexto da entidade (orçamento, OS, etc.).
  - `SendMessageButton` — abre `_SendMessageSheet` (bottom sheet).
  - `_SendMessageSheet` — seletor de canal, filtro de templates por canal, campo de corpo editável,
    botões "Só copiar" e "Abrir WhatsApp/e-mail"; após envio abre deep link e registra em `communication_logs`.
- `lib/features/communications/presentation/message_template_screen.dart`:
  - Listagem por canal com cards, toggle ativo/inativo, exclusão com confirmação.
  - Formulário `_TemplateForm` com chips de variáveis inseríveis no cursor.
- Rota `AppRoutes.messageTemplates` (`/configuracoes/templates-mensagem`) no router.
- Bloco "Templates de mensagem" em `SettingsScreen` com acesso à tela de templates e ação de carga de padrões.
- Botão "Enviar mensagem" (`SendMessageButton`) integrado em:
  - Detalhe de cliente (telefone/e-mail do próprio cliente).
  - Detalhe de OS (busca cliente pelo `customerDetailProvider`, passa `workOrderNumber` e `serviceTitle`).
  - Detalhe de orçamento (busca cliente pelo `customerDetailProvider`, passa `quotationNumber` e `amount`).

### Pendente (ação do desenvolvedor)

- Aplicar `0040_message_templates.sql` no Supabase.
- Carregar templates padrão via Configurações → "Carregar templates padrão".

---

## [F2-P2 — Permissões refinadas + Auditoria ampliada + Monitoramento + Backup/restore validado] — 2026-07-25

### Adicionado

- `supabase/migrations/0039_permissions_and_audit.sql`:
  - `cancel_quotation`: corrigido para verificar `has_permission('quotations.write')` (antes
    verificava apenas pertencimento ao tenant); adicionado `log_audit('quotation.cancelled')`.
  - `cancel_work_order`: corrigido para verificar `has_permission('work_orders.manage')` (antes
    verificava apenas pertencimento ao tenant); adicionado `log_audit('work_order.cancelled')`.
  - `create_new_quotation_version`: reescrita com `log_audit('quotation.new_version_created')`
    preservando toda a lógica de versionamento de `0037`.
  - `create_return_work_order`: reescrita com `log_audit('work_order.return_created')`
    preservando toda a lógica de retorno de `0038`.
  - RPC `list_audit_events(p_limit, p_entity, p_action)` SECURITY DEFINER: valida
    `audit.read`, retorna até 200 eventos do tenant com filtros opcionais por entidade e ação.
- `lib/features/settings/domain/audit_log_event.dart`: modelo `AuditLogEvent` com
  `entityLabel` e `actionLabel` em português para todas as ações auditadas.
- `lib/features/settings/data/audit_log_repository.dart`: `AuditLogRepository.listEvents`.
- `lib/features/settings/presentation/audit_log_screen.dart`: tela de trilha de auditoria
  com filtros por entidade (chips horizontais), lista paginada com "Carregar mais",
  cards neomórficos com ícone por entidade, rótulos legíveis e timestamp formatado.
- Rota `AppRoutes.auditLog` (`/configuracoes/auditoria`) no router.
- Bloco "Trilha de auditoria" em `SettingsScreen` visível para owner, admin e platform_admin.
- `scripts/validate_backup.sh`: dump via `pg_dump`, verificação de tabelas críticas,
  ausência de segredos, manifesto SHA-256 e restore opcional em banco de destino
  com contagens pós-restore.
- `docs/MVP_RELEASE_CHECK.md`: seção de backup/restore com pré-requisitos, cadência
  recomendada e nota sobre PITR do Supabase Pro.

### Corrigido

- `cancel_quotation` e `cancel_work_order` agora aplicam controle de acesso por permissão
  RBAC (não apenas por pertencimento ao tenant).

### Pendente (ação do desenvolvedor)

- Aplicar `0039_permissions_and_audit.sql` no Supabase (após 0036, 0037 e 0038).
- Executar `./scripts/validate_backup.sh` com `SUPABASE_DB_URL` real.

---

## [F2-P1 — Retornos de OS] — 2026-07-25

### Adicionado

- `supabase/migrations/0038_work_order_returns.sql`:
  - Coluna `parent_work_order_id UUID` em `work_orders` (auto-referência com
    `ON DELETE SET NULL`); índice parcial `idx_work_orders_parent`.
  - `event_type` CHECK expandido para incluir `'return_created'`
    (ALTER TABLE DROP/ADD constraint — expand-and-contract).
  - RPC `create_return_work_order(p_original_id, p_reason)` SECURITY DEFINER:
    valida tenant + permissão `work_orders.manage`, exige status `done`,
    cria OS com título prefixado `[Retorno]`, number via `next_sequence`,
    status `opened`; registra `return_created` na OS original e `created`
    na nova OS.
- `WorkOrder.parentWorkOrderId` e getter `isReturn` no domínio.
- `workOrderFromRow` lê `parent_work_order_id`.
- `WorkOrderRepository.createReturn(originalId, reason)`.
- `WorkOrderEvent.label` suporta `'return_created'` → "Retorno criado".
- Badge "Retorno" (chip terciário com ícone replay) no cabeçalho da OS de retorno.
- Botão "Criar retorno" (FilledButton, visível apenas quando `done`) na tela de detalhe.
- Diálogo reutilizável `_CancelReasonDialog` agora aceita `confirmLabel` e
  `confirmColor` — botão azul (cor primária) para retorno vs vermelho para cancelamento.
- Snackbar pós-criação com ação "Abrir" para navegar diretamente à OS de retorno.

### Pendente (ação do desenvolvedor)

- Aplicar `0038_work_order_returns.sql` no Supabase (após 0036 e 0037).

## [F2-P1 — Versionamento de orçamento + Histórico ampliado] — 2026-07-25

### Adicionado

- `supabase/migrations/0037_quotation_versioning.sql`: RPCs
  `create_new_quotation_version(p_quotation_id, p_items, p_notes)` —
  cria versão com número sequencial, recalcula totais, atualiza
  `current_version_id` e registra em `quotation_status_history`;
  `list_quotation_versions(p_quotation_id)` — retorna todas as versões
  com flag `is_current`. Ambas SECURITY DEFINER, validam tenant + permissão.
- `lib/features/quotations/domain/quotation_version.dart`: modelos
  `QuotationVersion` e `QuotationStatusEvent` + funções `fromRow`.
- `lib/features/work_orders/domain/work_order_event.dart`: modelo
  `WorkOrderEvent` com `label` humanizado + `fromRow`.
- `QuotationRepository.listVersions(quotationId)` e
  `QuotationRepository.createNewVersion({quotationId, items, notes})`.
- `QuotationRepository.listStatusHistory(quotationId)` — lê
  `quotation_status_history` diretamente via PostgREST.
- `WorkOrderRepository.listEvents(workOrderId)` — lê `work_order_events`.
- Providers Riverpod: `quotationVersionsProvider`, `quotationStatusHistoryProvider`,
  `workOrderEventsProvider` (todos autoDispose.family).
- `_QuotationVersionsPanel`: lista versões com círculo numerado, total e data
  na tela de detalhe do orçamento.
- `_QuotationHistoryPanel`: linha do tempo de status com notas e timestamps
  na tela de detalhe do orçamento.
- `_WorkOrderEventsPanel`: linha do tempo de eventos com label humanizado
  na tela de detalhe da OS.

### Corrigido (na migration 0036)

- `work_order_events` usava coluna `kind` (inexistente) → corrigido para
  `event_type`; faltava `tenant_id` no INSERT → adicionado.
- `quotation_status_history` não existia como tabela — criada na `0036`
  com RLS e índice parcial.

### Pendente (ação do desenvolvedor)

- Aplicar `0036_cancellations.sql` e `0037_quotation_versioning.sql` no
  Supabase remoto (SQL Editor → colar → Run, nessa ordem).

## [F2-P1 — Cancelamentos controlados] — 2026-07-25

### Adicionado

- `supabase/migrations/0036_cancellations.sql`: colunas `cancelled_at TIMESTAMPTZ`
  e `cancellation_reason TEXT` nas tabelas `quotations` e `work_orders`; índices
  parciais `idx_quotations_cancelled_at` e `idx_work_orders_cancelled_at` para
  auditoria; RPCs `cancel_quotation(p_quotation_id, p_reason)` e
  `cancel_work_order(p_work_order_id, p_reason)` — SECURITY DEFINER, validam
  tenant membership, status permitido e motivo não-nulo.
- `Quotation.cancelledAt` e `Quotation.cancellationReason` no modelo de domínio;
  `quotationFromRow()` atualizado.
- `WorkOrder.cancelledAt` e `WorkOrder.cancellationReason` no modelo de domínio;
  `workOrderFromRow()` atualizado.
- `QuotationRepository.cancel(id, reason)` — chama RPC `cancel_quotation`.
- `WorkOrderRepository.cancel(id, reason)` — chama RPC `cancel_work_order`.
- Botão "Cancelar orçamento" na tela `quotation_detail_screen.dart`: visível
  apenas para status não-terminais; abre `_CancelReasonDialog` com motivo
  obrigatório (até 300 chars); exibe painel de motivo+data quando cancelado.
- Botão "Cancelar OS" na tela `work_order_detail_screen.dart`: oculto para
  `done` e `cancelled`; abre `_CancelReasonDialog`; exibe painel de motivo+data.
- Widget `_CancelReasonDialog` (StatefulWidget com FormValidator) nas duas telas.

### Regras de negócio

- Orçamentos `approved` ou `cancelled` não podem ser cancelados (exceção P0001).
- OS `done` ou `cancelled` não podem ser canceladas (exceção P0001).
- Motivo em branco é rejeitado no banco (antes de persistir).
- `cancel_quotation` registra em `quotation_status_history`; `cancel_work_order`
  insere evento `status_changed` em `work_order_events`.

### Pendente (ação do desenvolvedor)

- Aplicar migration `0036_cancellations.sql` no Supabase remoto:
  SQL Editor → colar conteúdo do arquivo → Run.

## [F2 — Preparação da publicação em staging] — 2026-07-24

### Adicionado

- `dart_defines/staging.json` criado (gitignored), reaproveitando `SUPABASE_URL`/
  `SUPABASE_ANON_KEY` do projeto `Service_Saas` já usado em desenvolvimento —
  decisão registrada: staging usa o mesmo projeto Supabase de dev, não um
  projeto isolado, por escolha explícita do usuário.
- `docs/FASE2_RUNBOOK_STAGING.md`: runbook completo de T2.1 a T2.5 (build,
  publicação manual via Gerenciador de Arquivos da Hostinger, smoke test
  remoto, backup do banco, checklist DNS/HTTPS), com checklist de saída.

### Alterado

- `docs/DEPLOY_STAGING.md`, `docs/MVP_RELEASE_CHECK.md`,
  `docs/RELEASE_NOTES_MVP.md`: URL de staging genérica (`<url-staging>` /
  `staging.seudominio.com`) substituída pela URL real
  `https://cliente.leonardoperescouto.com`; contagem de migrations corrigida
  de `0001-0013` (desatualizada) para `0001-0035`.

### Observação

Publicação real não foi executada — depende de Flutter local (build) e do
Gerenciador de Arquivos da Hostinger (upload manual, fora do alcance do
sandbox de análise). Como staging compartilha o banco com dev, a Fase 1
(isolamento RLS) deve ser concluída antes de publicar.

## [F1 — Preparação da validação de segurança RLS] — 2026-07-24

### Adicionado

- Reescritos `test/isolation/0007` a `0013` como testes SQL automatizados
  (antes eram roteiros manuais comentados, sem asserção nem checagem de
  isolamento entre tenants). Agora seguem o padrão de `0002`-`0005`: blocos
  `DO $$ ... $$` com `RAISE EXCEPTION` em falha, verificação cross-tenant
  (`insufficient_privilege` esperado para acesso de outro tenant) e rollback
  automático dos dados de teste.
- `supabase/seed/dev_seed.sql` reescrito: agora cria 5 usuários de teste
  (owner, technician, viewer, analyst no tenant Alpha; owner no tenant Beta)
  com placeholders de UUID válidos e consistentes com todos os arquivos de
  `test/isolation/*.sql`, permitindo substituição em lote.
- `scripts/create_test_users.sh`: cria os 5 usuários de teste via Supabase
  Auth Admin API.
- `scripts/apply_test_uuids.sh`: substitui os placeholders pelos UUIDs reais
  em cópias geradas em `test/_generated/` (gitignored).
- `scripts/run_isolation_tests.sh`: executa os 12 testes gerados em sequência
  e produz relatório PASS/FAIL consolidado.
- `docs/FASE1_RUNBOOK_SEGURANCA_RLS.md`: runbook completo da Fase 1, com
  checklist de saída e aviso de que os testes reescritos ainda não foram
  executados (ambiente de análise sem PostgreSQL/acesso root).

### Observação

Nenhum teste foi executado nesta sessão — apenas preparado. Recomenda-se
rodar primeiro contra um Supabase local (`supabase start` + `supabase db
reset`) antes do projeto remoto `Service_Saas`, para isolar eventuais erros
de sintaxe de eventuais falhas reais de isolamento.

## [F0 — Higiene técnica pré-produção] — 2026-07-24

### Corrigido

- Resolvida colisão de prefixo de migration: `0034_list_all_active_professionals_in_schedule.sql`
  renumerada para `0035_list_all_active_professionals_in_schedule.sql` (a outra migration `0034`,
  `tenant_billing_webhook_events`, é a versão histórica já documentada e permanece inalterada).
- Criado rollback ausente `0035_list_all_active_professionals_in_schedule_rollback.sql`,
  restaurando o comportamento anterior de `list_tenant_technicians()` definido em `0018`.
- Sequência de migrations validada: `0001`–`0035` contígua, sem lacunas ou duplicidades.

## [F2 — Hubs dos módulos comerciais dos planos] — 2026-07-23

### Adicionado
- Rotas e telas-base para `Pagamentos`, `Fiscal`, `Promoções`, `Campanhas`, `BI avançado` e `IA`.
- Novo componente reutilizável `ModulePlaceholderScreen` para abrir módulos planejados com contexto operacional, escopo da fase e próximos incrementos.
- Tela operacional inicial de `Pagamentos`, baseada nos recebíveis existentes, com visão de pendências, vencidos, liquidados e ação direta de baixa manual.
- Tela operacional inicial de `Fiscal`, baseada nos recibos e recebíveis existentes, com visão documental, pendências de conferência e abertura direta do PDF do documento emitido.

### Alterado
- O menu principal agora exibe esses módulos quando o plano do tenant libera a feature correspondente.
- O dashboard ganhou atalhos rápidos para os novos módulos premium, respeitando o plano ativo.
- O roteador passou a mapear as novas rotas para bloqueio por feature flag do plano, mantendo coerência entre navegação e assinatura.
- A barra lateral desktop passou a usar rolagem interna no `NavigationRail` e menu de usuário desacoplado do bloco de destinos, evitando overflow vertical quando muitos módulos ficam liberados no plano Enterprise.

## [F2 — Onboarding por convite e bloqueio comercial] — 2026-07-23

### Adicionado
- Tela pública `/aceitar-convite` para primeiro acesso de usuários convidados.
- Fluxo de criação de conta a partir do convite, com validação do token, exibição da empresa/papel e aceite automático após definir a senha.
- Tela de bloqueio comercial `/assinatura` para trial expirado, assinatura pendente ou cancelada.
- Tela `/onboarding-plano` para confirmação obrigatória do plano inicial logo após criar a empresa.
- Migration `0029_plan_selection_onboarding.sql` com `plan_selected_at` e RPC `complete_current_tenant_plan_selection(...)`.
- Migration `0030_tenant_billing_history.sql` com tabela `tenant_billing_events`, função de log comercial e RPC para atualizar manualmente o status da assinatura.
- Migration `0031_tenant_checkout_sessions.sql` com sessões de checkout rastreáveis, retorno de cobrança e auditoria comercial.
- Migration `0032_tenant_checkout_confirmation.sql` com confirmação do checkout e ativação comercial automática do tenant.
- Migration `0033_tenant_checkout_session_closure.sql` com cancelamento e expiração de sessões de checkout.
- Migration `0034_tenant_billing_webhook_events.sql` com registro, processamento e histórico de webhooks de cobrança.

### Alterado
- O link gerado em `Configurações > Membros e acesso` agora aponta para a tela de aceite de convite, em vez de cair no login genérico.
- A navegação do app passou a redirecionar tenants com bloqueio comercial para a tela de assinatura, preservando acesso a `Configurações` e ao link público de orçamento.
- O fluxo de criação da empresa agora exige confirmação comercial do plano antes de liberar o dashboard.
- A área `Configurações > Plano e assinatura` agora mostra a linha do tempo comercial e permite registrar alterações de status até a entrada do gateway de cobrança.
- O onboarding de plano e a tela de assinatura agora podem abrir checkout externo e portal de cobrança com URLs configuradas por ambiente.
- A área de assinatura agora lista sessões recentes de checkout e permite confirmar manualmente o pagamento para ativar o plano antes da entrada do webhook do gateway.
- As sessões de checkout agora podem ser encerradas como canceladas ou expiradas, com histórico comercial completo.
- A área de assinatura agora também registra webhooks recentes e permite simular eventos de cobrança para aprovar, cancelar ou expirar uma sessão automaticamente.
- A abertura do checkout agora cria uma sessão comercial persistida no banco e o retorno ao app registra o evento antes da confirmação final do pagamento.

### Testes
- Atualizados os testes de redirecionamento do router para cobrir convite público, onboarding sem tenant e bloqueio comercial.

## [F2 — Base de planos e assinatura] — 2026-07-23

### Adicionado
- Estrutura base de planos SaaS com `Starter`, `Professional`, `Business` e `Enterprise`, incluindo limites de usuários e unidades.
- Migration `0022_tenant_subscription_plans.sql` adiciona `plan_key`, `billing_status` e `trial_ends_at` em `tenants`, preservando tenants existentes com acesso amplo e configurando novos tenants para `Starter + 14 dias de trial`.
- Migration `0024_tenant_plan_limits.sql` passa a impor limite real de usuários ativos por plano e bloqueia downgrade para pacote menor que o uso atual.
- Modelo Flutter `TenantPlanDefinition` com catálogo central de features por plano.

### Alterado
- O shell principal e o dashboard passam a respeitar os módulos liberados pelo plano do tenant.
- O dashboard agora mostra plano atual, status da assinatura/trial e limites comerciais do tenant.
- A tela `Configurações` agora mostra consumo atual de usuários ativos dentro do plano contratado.

## [F2 — Cadastro formal de profissionais] — 2026-07-22

### Adicionado
- Nova área `Profissionais` no menu principal para cadastrar equipe interna e parceiros operacionais.
- Cadastro neomórfico de profissional com tipo `Interno` ou `Parceiro`, categoria/especialidade, contato, observações e status ativo/inativo.
- Profissionais internos podem ser vinculados a um usuário técnico ativo do tenant, habilitando uso direto na agenda.
- Migration `0018_service_professionals.sql` cria a tabela `service_professionals`, RLS, índices, bootstrap dos técnicos já existentes e função `list_tenant_technician_users()`.

### Alterado
- A agenda diária deixou de inferir categoria pelo nome e passou a usar a categoria real cadastrada para os profissionais.
- A função `list_tenant_technicians()` agora retorna o cadastro formal de profissionais internos ativos, preservando o agendamento apenas para quem estiver vinculado a usuário interno.

## [F2 — Anexos de orçamento e OS] — 2026-07-22

### Corrigido
- O seletor reutilizável de anexos passou a usar modo nativo de imagem no navegador para cadastros só com foto, reduzindo a chance de o botão não abrir no web.
- O componente agora trata falhas de abertura do seletor com feedback visual ao usuário.

### Adicionado
- Orçamentos e OS agora aceitam fotos e documentos no cadastro inicial.
- Evidências da OS agora aceitam também documentos Office e texto, além de fotos, vídeos e PDF.
- Migration `0016_attachment_documents.sql` amplia os MIME types aceitos em `quotation_attachments` e no bucket `work-order-evidence`.

## [F2 — Importação CSV de clientes] — 2026-07-22

### Adicionado
- Tela de clientes ganhou ação `Importar clientes` no topo, abrindo popup neomórfico para carga em lote por CSV.
- O importador lê arquivo com cabeçalho, valida nome, CPF/CNPJ, telefone, CEP e UF antes de gravar.
- O fluxo reaproveita o cadastro existente de cliente, contato principal e endereço padrão, mantendo as mesmas regras de negócio e RLS.
- A importação detecta duplicidade por CPF/CNPJ e telefone contra a base atual e também dentro do próprio arquivo.
- Quando o endereço vier parcial, o cliente é importado e a pendência fica explícita no resumo final para edição posterior.
- `test/customers/customer_import_test.dart` cobre o parser CSV e validações básicas.

### Operação
- Escopo atual: CSV com colunas como `tipo`, `nome`, `nome_fantasia`, `cpf_cnpj`, `email`, `telefone`, `contato`, `contato_telefone`, `cep`, `logradouro`, `numero`, `complemento`, `bairro`, `cidade`, `uf` e `observacoes`.

## [F2 — Composição de orçamento e OS] — 2026-07-22

### Adicionado
- Orçamento passou a aceitar múltiplas linhas na própria criação, incluindo serviço, HH, material, deslocamento, extra e outros itens.
- Cada linha pode carregar `Profissional / especialidade` no descritivo, permitindo compor propostas com eletricista, bombeiro hidráulico e outros perfis na mesma proposta.
- OS manual passou a aceitar múltiplas linhas de execução no cadastro inicial, com HH, materiais e extras, recalculando o valor previsto a partir da composição.
- Detalhe do orçamento agora mostra a composição das linhas gravadas em `quotation_items`.
- Detalhe da OS agora mostra a composição das linhas gravadas em `work_order_items`.

### Técnica
- `QuotationRepository` ganhou leitura de `quotation_items`.
- `WorkOrderRepository.create(...)` passou a aceitar itens iniciais e gravá-los em `work_order_items`.
- `WorkOrderRepository` ganhou leitura de `work_order_items`.

## [F2 — Agenda diária por profissional] — 2026-07-22

### Adicionado
- Clique no dia do calendário agora abre uma agenda diária ampliada, inspirada no layout de referência, com painel lateral de profissionais e visão geral.
- A agenda diária ganhou filtros por categoria profissional com classificação operacional imediata no app, incluindo casos como eletricista, bombeiro hidráulico e refrigeração quando identificados pelo nome do profissional.
- Cada horário livre pode abrir popup de agendamento de `Orçamento` ou `OS`.
- O popup de agendamento agora suporta busca de cliente por nome, CPF/CNPJ ou telefone.
- No fluxo de orçamento, o popup permite localizar e vincular o chamado antes de gravar a visita.
- No fluxo de OS, o popup permite localizar a ordem já existente e também abrir o cadastro de nova OS antes do agendamento.

### Técnica
- `AppointmentFormNotifier` ganhou `scheduleAppointment(...)` para suportar agendamento genérico de visita/orçamento e OS com a mesma base.
- A agenda mensal continua como entrada principal, mas o drill-down diário passou a ser o centro operacional da marcação de horários.

## [F2 — Geolocalização de endereços] — 2026-07-22

### Adicionado
- Serviço `AddressGeocoder` para buscar latitude/longitude de endereços brasileiros via OpenStreetMap/Nominatim.
- Bloco neomórfico `Localização para rotas` no cadastro de novo cliente e na edição/criação de endereços do cliente.
- Botão `Localizar`/`Atualizar` para preencher coordenadas do endereço depois do CEP e dos campos principais.
- Salvamento de latitude/longitude no endereço padrão criado junto com o cliente e nos endereços editados.

### Operação
- Sem nova migration: `customer_addresses` já possuía campos `latitude` e `longitude`.
- As rotas continuam abrindo por endereço textual quando não houver coordenadas; com coordenadas, o roteiro sugerido passa a calcular distância com mais precisão.

## [F2 — Rotas de campo] — 2026-07-22

### Adicionado
- Botao `Rota` nos cards de Chamados, Orcamentos e OS, com opcoes para Google Maps, Waze, Apple Maps e copia do endereco.
- Painel `Roteiro sugerido` nas listas de Chamados, Orcamentos e OS.
- Algoritmo local `suggestFieldRoute()` para ordenar atendimentos por criticidade/prioridade, horario/validade e distancia quando houver coordenadas.
- Repositorios passaram a anexar endereco de rota a partir do endereco do atendimento ou endereco principal do cliente.
- Dependencia `url_launcher` para abrir apps externos de mapa em celular/tablet.

### Observacao operacional
- Distancia aproximada depende de latitude/longitude no cadastro de endereco. Sem coordenadas, os apps de mapa ainda abrem pelo endereco textual.

## [F2 — Fotos por etapa] — 2026-07-22

### Adicionado
- Componente reutilizavel `PhotoAttachmentPicker` para selecionar multiplas fotos em popups neomorficos.
- Cadastro de novo chamado ganhou campo de fotos para identificacao de cliente, equipamento, local e servico.
- Cadastro de novo orcamento ganhou campo de fotos para apoiar cotacao, catalogo e historico visual.
- Cadastro de nova OS ganhou campo de fotos iniciais, usando o Storage privado de evidencias da OS.
- Migration `0015_quotation_attachments.sql` com tabela `quotation_attachments`, bucket privado `quotation-attachments`, RLS e rollback.

### Segurança
- Fotos de chamados, orcamentos e OS ficam em buckets privados por tenant, com caminho iniciado por `tenant_id` e policies baseadas em permissao do modulo.

### Operação
- Migration `0015` aplicada no Supabase remoto existente.

## [F2 — Pesquisa de satisfação] — 2026-07-22

### Adicionado
- Migration `0014_customer_satisfaction.sql` com tabela `work_order_satisfaction`, RLS, rollback e RPC auditada `record_work_order_satisfaction()`.
- Roteiro SQL manual `test/isolation/0013_customer_satisfaction_test.sql`.
- Domínio `WorkOrderSatisfaction`, leitura no repositório de OS e provider `workOrderSatisfactionProvider`.
- Detalhe da OS ganhou botão `Registrar satisfação`, habilitado para OS concluída, abrindo popup neomórfico com nota de 1 a 5, respondente e comentário.
- Detalhe da OS exibe painel de satisfação registrada ou estado vazio quando ainda não há avaliação.
- Relatórios passaram a consolidar satisfação com média, contagem de avaliações e avaliações críticas, também no resumo copiado e na exportação CSV.

### Segurança
- A RPC valida tenant ativo, permissão `work_orders.execute` ou `work_orders.manage`, exige OS concluída e gera auditoria `work_order.satisfaction.recorded`.

### Operação
- Migration `0014` aplicada no Supabase remoto existente.

### Pendente
- Executar teste SQL com usuários reais.

## [F2 — Relatórios básicos] — 2026-07-22

### Adicionado
- `lib/features/reports/` — snapshot gerencial, repositório, provider e tela de Relatórios neomórfica.
- Rota `/relatorios` e entrada "Relatórios" no menu responsivo.
- Indicadores de clientes ativos, chamados abertos, agendamentos pendentes, OS abertas/concluídas, pipeline de orçamentos, saldo em aberto, vencido e recebido.
- Filtro por período: `30 dias`, `Mês atual`, `Ano atual` e `Tudo`.
- Botão "Copiar resumo" para levar os principais números gerenciais para a área de transferência.
- Botão "Exportar CSV" para baixar o resumo filtrado em planilha simples.
- Gráfico "Tendência mensal" com chamados, OS concluídas e recebimentos no período filtrado.
- Seção "Clientes em destaque" com ranking por recebimentos, saldo em aberto, chamados e OS no período.
- Seção "Tipos de serviço em alta" com ranking por chamados, abertos e fechados no período.
- Seção "Técnicos em campo" com ranking por agendamentos, apontamentos e horas trabalhadas.
- Popups de detalhe nos rankings de cliente, tipo de serviço e técnico.
- Drill-down analítico inicial nos popups, exibindo movimentos recentes do período por cliente, tipo de serviço e técnico.
- Componente reutilizavel `AppFormSection`/`AppFormGrid` para cadastros com campos lado a lado, secoes neomorficas e quebra responsiva.
- Cadastros de empresa, cliente, chamado, orçamento, OS, agendamento, pagamento, contatos, endereços e ações de OS reorganizados para o padrão horizontal do layout de referência.
- Popup de novo cliente agora cria contato principal e endereco padrao no primeiro cadastro; contato espelha nome/telefone do cliente por padrão, mas permanece editavel.
- Cadastro de cliente ganhou busca automatica de CEP para preencher rua, bairro, cidade e UF.
- Lista e detalhe de clientes ganharam botao visivel `Editar cliente`, abrindo a edicao em popup.
- Popup de novo chamado ganhou campo Cliente pesquisavel por nome, CPF, CNPJ ou telefone dentro da propria lista de sugestoes.
- Faixa "Filtros de análise" nos Relatórios, com busca nos rankings e filtro por situação: todos, em aberto, fechados, financeiro e agenda.
- CSV inclui linhas mensais, linhas por cliente, tipo de serviço e técnico.
- Exportação CSV agora respeita a busca digitada, o filtro de situação e os rankings filtrados visíveis na tela.
- `test/reports/reports_screen_test.dart` cobre a renderização dos indicadores principais e abertura dos popups de ranking.
- `test/reports/reports_csv_export_test.dart` cobre geração do conteúdo CSV e nome do arquivo.

### Segurança
- Sem nova migration: os relatórios usam tabelas existentes e continuam limitados pelo RLS do Supabase.

### Corrigido
- Usuario autenticado com empresa ativa agora sai automaticamente de `/criar-empresa` para `/dashboard`, evitando recriar empresa e receber erro de identificador ja cadastrado.

### Pendente
- Validação em staging com dados reais e refinamentos de drill-down conforme uso operacional.

## [Entrega 8 — Financeiro mínimo] — 2026-07-22

### Segurança
- Migration `0013_financials_minimum.sql` cria RLS para recebíveis, pagamentos manuais e recibos.
- Criação de cobrança exige `financials.write`, valida tenant ativo e gera recebível idempotente por OS.
- Baixa manual exige `financials.write`, bloqueia valor acima do saldo, atualiza saldo em transação e gera auditoria `financial.payment.registered`.

### Adicionado
- `docs/DOCS_INDEX.md` centraliza os documentos principais do projeto.
- `docs/SYSTEM_MANUAL.md` documenta fluxos, modulos, operacao e padrao visual do sistema.
- `docs/SQL_MANUAL.md` documenta Supabase, migrations, RLS, Storage, seeds e validacoes SQL.
- `docs/RECREATE_PROMPT.md` cria um prompt mestre para reconstruir o ServiceFlow do zero.
- `lib/features/financials/` — domínio de recebíveis, repositório, provider e tela financeira neomórfica.
- Rota `/financeiro` e entrada "Financeiro" no shell responsivo.
- Cards de resumo financeiro: saldo em aberto, vencido e quantidade de recebíveis.
- Popup "Baixa manual" para registrar pagamento por Pix manual, dinheiro, transferência, cartão ou outro.
- Botão "Gerar cobrança" no detalhe da OS, criando recebível financeiro a partir do valor da ordem.
- Botão "Visualizar recibo" nos recebíveis com pagamento registrado.
- `ReceiptPdfGenerator` gera PDF de recibo com identidade ServiceFlow, número do recibo, cliente, valor, forma de pagamento e referência.
- Dashboard mínimo agora exibe resumo financeiro com saldo em aberto, vencido, total de recebíveis e atalho para Financeiro.
- `supabase/migrations/0013_financials_minimum.sql`, rollback e roteiro `test/isolation/0012_financials_minimum_test.sql`.
- `scripts/build_staging.sh` gera build web otimizado e pacote `.zip` para publicação em staging.
- `scripts/write_release_manifest.sh` gera manifesto com tamanho, commit e SHA-256 do pacote.
- `scripts/smoke_web.sh` valida homepage, rota de login e assets principais em localhost ou URL publicada.
- `scripts/security_preflight.sh` verifica segredos, arquivos de ambiente no bundle/pacote, rollbacks e migrations remotas.
- `scripts/release_check.sh` executa análise, testes críticos, build web e smoke test em uma única rotina de pré-release.
- `docs/DEPLOY_STAGING.md` documenta publicação na Hostinger, smoke test e rollback.
- `docs/MVP_RELEASE_CHECK.md` registra o último release check local e pendências externas.
- `docs/RELEASE_NOTES_MVP.md` consolida escopo entregue, validações, arquivos de publicação e rollback.
- `web/.htaccess` adiciona headers de cache e MIME types compatíveis com hospedagem Apache/Hostinger.

### Testes
- `flutter analyze` — sem issues.
- `flutter test test/dashboard/dashboard_screen_test.dart` — passou.
- `flutter test test/financials/financial_list_screen_test.dart` — passou.
- `flutter test test/financials/receipt_pdf_generator_test.dart` — passou.
- `flutter test test/work_orders/work_order_detail_screen_test.dart` — passou.
- `./scripts/smoke_web.sh http://127.0.0.1:8091` — passou.
- `./scripts/release_check.sh dart_defines/dev.json 8091` — passou.
- `./scripts/security_preflight.sh dist/serviceflow-staging-dry-run.zip --remote` — passou.
- Supabase remoto `Service_Saas` verificado: migrations `0001` a `0013` alinhadas; tabelas `receivables`, `payment_records`, `receipts` e RPCs financeiros confirmados.

### Operação
- Migration `0013` aplicada no Supabase remoto existente e histórico reparado para a CLI reconhecer a versão aplicada.
- Pacote local de preview gerado em `dist/serviceflow-local-preview.zip`.
- Manifesto SHA-256 gerado para `dist/serviceflow-staging-dry-run.zip`.
- Pendente na E8: publicar em staging Hostinger, rodar smoke test na URL publicada e executar o teste SQL com usuários reais.

## [Entrega 7 — OS e execução] — 2026-07-22

### Segurança
- Migration `0008_work_orders.sql` cria RLS para ordens de serviço, itens, eventos e evidências.
- Conversão de orçamento para OS exige `work_orders.write`, valida tenant ativo e aceita apenas orçamento aprovado.
- Conversão é idempotente por `quotation_id`, evitando duplicar OS para o mesmo orçamento.
- Transição de execução exige `work_orders.execute` ou `work_orders.manage` e bloqueia alteração de OS finalizada.
- Migration `0009_work_order_execution.sql` cria RLS para horas trabalhadas e materiais aplicados.
- Registro de horas e materiais exige `work_orders.execute`, bloqueia OS finalizada e gera auditoria.
- Migration `0010_work_order_acceptance.sql` cria RLS para aceite básico do cliente.
- Aceite exige `work_orders.execute` ou `work_orders.manage`, conclui a OS quando necessário e gera auditoria `work_order.acceptance.recorded`.
- Migration `0011_work_order_expenses.sql` cria RLS para despesas operacionais da OS.
- Despesas exigem `work_orders.execute`, bloqueiam OS finalizada e geram auditoria `work_order.expense.created`.
- Migration `0012_work_order_evidence_storage.sql` cria bucket privado para evidências da OS e RPC auditado para registrar anexos.
- Evidências exigem `work_orders.execute`, validam tenant pelo caminho de Storage e ficam isoladas por empresa.
- Auditoria registra criação a partir de orçamento e mudança de status.

### Adicionado
- `lib/features/work_orders/` — domínio, repositório, provider de lista, tela de lista, criação em popup, detalhe e chip de status.
- Rotas `/ordens-servico`, `/ordens-servico/novo`, `/ordens-servico/:id` e entrada "OS" no shell responsivo.
- RPC `convert_approved_quotation_to_work_order()` para gerar OS a partir de orçamento aprovado.
- RPC `transition_work_order()` para iniciar, pausar, concluir ou cancelar execução.
- Botão "Gerar OS" no detalhe do orçamento aprovado, levando direto para a OS criada.
- Botões "Registrar horas" e "Adicionar material" no detalhe da OS, ambos em popup neomórfico.
- Botão "Registrar aceite" no detalhe da OS, com popup para nome do responsável, documento parcial e observações.
- Botão "Registrar despesa" no detalhe da OS, com popup para tipo, valor e descrição.
- Botão "Anexar evidência" no detalhe da OS, com upload de imagem, vídeo ou PDF para Storage privado.
- Aceite do cliente agora inclui área de assinatura desenhada, salva como evidência da OS.
- `supabase/migrations/0008_work_orders.sql`, rollback e roteiro `test/isolation/0007_work_orders_test.sql`.
- `supabase/migrations/0009_work_order_execution.sql`, rollback e roteiro `test/isolation/0008_work_order_execution_test.sql`.
- `supabase/migrations/0010_work_order_acceptance.sql`, rollback e roteiro `test/isolation/0009_work_order_acceptance_test.sql`.
- `supabase/migrations/0011_work_order_expenses.sql`, rollback e roteiro `test/isolation/0010_work_order_expenses_test.sql`.
- `supabase/migrations/0012_work_order_evidence_storage.sql`, rollback e roteiro `test/isolation/0011_work_order_evidence_storage_test.sql`.

### Performance
- `web/index.html` agora exibe uma splash neomórfica imediatamente antes do Flutter terminar de carregar, evitando tela branca no primeiro acesso.
- Build local gerado sem source maps e sem service worker PWA para reduzir artefatos e evitar cache antigo durante testes locais.

### Testes
- `flutter analyze` — sem issues.
- `flutter test test/work_orders/work_order_list_screen_test.dart` — passou.
- `flutter test test/work_orders/work_order_detail_screen_test.dart` — passou.
- `flutter test test/quotations/quotation_detail_screen_test.dart test/work_orders/work_order_list_screen_test.dart test/router/app_router_redirect_test.dart` — passou.
- Supabase remoto `Service_Saas` verificado: migrations `0001` a `0012` alinhadas; bucket privado e funções de OS confirmados.

### Operação
- Migrations `0008`, `0009`, `0010`, `0011` e `0012` aplicadas no Supabase remoto existente e histórico reparado para a CLI reconhecer as versões aplicadas.
- Ainda pendente para validação operacional total da E7: executar o roteiro SQL de OS com usuários reais do ambiente.

## [Entrega 6 — Link público] — 2026-07-21

### Segurança
- Migration `0005_quotations.sql` cria RLS para orçamentos, versões, itens, links públicos e aprovações.
- `tenant_id` é derivado no servidor e cliente/chamado são validados contra o tenant ativo.
- `create_quotation()` exige `quotations.write`, valida ao menos um item e calcula totais no banco.
- Valores monetários usam centavos inteiros no app e no banco para evitar arredondamento indevido.
- Auditoria registra `quotation.created`.
- Migration `0006_quotation_public_flow.sql` cria token público opaco com hash SHA-256 no banco, expiração padrão de 15 dias e funções SECURITY DEFINER para acesso/decisão pública.
- Geração do link exige `quotations.send`; aprovação/rejeição pública registra decisão em `quotation_approvals` e auditoria `quotation.public_decision`.
- Migration `0007_quotation_public_revoke.sql` permite revogar links públicos ativos do orçamento com validação de tenant, permissão `quotations.send` e auditoria `quotation.public_link.revoked`.

### Adicionado
- `lib/features/quotations/domain/` — `Quotation`, `QuotationStatus`, `QuotationItemKind`, itens e payloads.
- `lib/features/quotations/data/quotation_repository.dart` — listagem, detalhe e criação via RPC.
- `lib/features/quotations/application/` — notifiers/providers de lista, detalhe e formulário.
- `lib/features/quotations/presentation/` — lista, criação e detalhe de orçamento.
- Rotas `/orcamentos`, `/orcamentos/novo`, `/orcamentos/:id` e entrada "Orçamentos" no shell responsivo.
- `supabase/migrations/0005_quotations.sql`, rollback e `test/isolation/0005_rls_quotations_test.sql`.
- `test/quotations/` — testes de domínio, formulário e tela de lista.
- Tela pública `/orcamento-publico/:token` para cliente aprovar, rejeitar ou solicitar alteração.
- Botão "Copiar link público" no detalhe do orçamento.
- Geração de PDF do orçamento no detalhe, com layout ServiceFlow e fonte Roboto embutida para suporte a acentos em português.
- Botão "Revogar link público" no detalhe do orçamento, com confirmação antes de invalidar links enviados.
- Agenda redesenhada em calendário mensal neomórfico, com navegação por mês, estados livre/ocupado/fechado e popup de agendamento ao clicar no dia.
- Cadastros de novo cliente, novo chamado e novo orçamento agora abrem em popups neomórficos sobre a tela atual.
- `supabase/migrations/0006_quotation_public_flow.sql` e rollback correspondente.
- `supabase/migrations/0007_quotation_public_revoke.sql`, rollback e roteiro `test/isolation/0006_public_quotation_link_test.sql`.

### Corrigido
- Fluxo pós-login agora considera a sessão inicial do Supabase e aguarda carregamento da empresa antes de redirecionar.
- Criação/login/logout invalidam o cache de membership, evitando ficar preso em `/login` ou `/criar-empresa`.
- Tema, login, criação de empresa e dashboard receberam componentes neomórficos reutilizáveis.
- Links públicos de orçamento permanecem acessíveis mesmo quando o usuário atual já está logado.

### Testes
- `flutter analyze` — sem issues.
- `flutter test` — todos os testes passaram.
- `flutter build web --dart-define-from-file=dart_defines/dev.json` — build web concluído.
- Preview do PDF renderizado via Poppler para inspeção visual.
- Supabase remoto `Service_Saas` verificado: migrations `0001` a `0007` alinhadas; funções públicas de orçamento confirmadas.

### Operação
- Migrations `0005`, `0006` e `0007` aplicadas no Supabase remoto existente e histórico reparado para a CLI reconhecer as versões aplicadas.
- Ainda pendente para validação operacional total da E6: executar o roteiro SQL do link público com usuários reais do ambiente.

## [Entrega 5] — 2026-07-21

### Segurança
- Migration `0004_scheduling.sql` cria RLS para agendamentos, atribuições, visitas técnicas e evidências.
- `tenant_id` é derivado no servidor para usuários autenticados e propagado por triggers nas tabelas filhas.
- `schedule_appointment()` valida permissão `appointments.write`, técnico ativo no tenant, chamado/cliente/endereço do mesmo tenant e período válido.
- Conflito de agenda por técnico é bloqueado de forma transacional com lock consultivo e validação de sobreposição de horários.
- MVP aceita apenas visita técnica vinculada a chamado; uso de ordem de serviço na agenda fica bloqueado até a Entrega 7.
- Auditoria registra `appointment.scheduled`.

### Adicionado
- `lib/features/scheduling/domain/` — `Appointment`, `AppointmentKind`, `AppointmentStatus` e `Technician`.
- `lib/features/scheduling/data/appointment_repository.dart` — listagem, detalhe, criação via RPC e listagem de técnicos.
- `lib/features/scheduling/application/` — notifiers/providers de lista, formulário e técnicos.
- `lib/features/scheduling/presentation/` — tela de agenda, criação de agendamento, detalhe e chip de status.
- Rotas `/agenda`, `/agenda/novo`, `/agenda/:id` e entrada "Agenda" no shell responsivo.
- `supabase/migrations/0004_scheduling.sql` e rollback.
- `test/scheduling/` — testes de domínio, formulário e tela de lista.
- `test/isolation/0004_rls_scheduling_test.sql` — roteiro SQL para isolamento, conflito de horário e criação automática de visita técnica.

### Testes
- `flutter analyze` — sem issues.
- `flutter test` — todos os testes passaram.
- `flutter build web --dart-define-from-file=dart_defines/dev.json` — build web concluído.
- Supabase remoto `Service_Saas` verificado: migrations `0001`, `0002`, `0003`, `0004` alinhadas; tabelas e funções de agenda confirmadas.

### Operação
- Migration `0004` aplicada no Supabase remoto existente e histórico reparado para a CLI reconhecer a versão aplicada.

## [Entrega 4] — 2026-07-21

### Segurança
- Migration `0003_service_requests.sql` cria RLS para categorias, prioridades, chamados, histórico, anexos, notas e atribuições.
- `tenant_id` de chamados é derivado no servidor para usuários autenticados; operações administrativas/seed exigem `tenant_id` explícito.
- Chamada cross-tenant é bloqueada por validação server-side de cliente, contato, endereço, categoria e prioridade.
- Status do chamado não pode ser alterado livremente por UPDATE; transições devem passar por `transition_service_request()`.
- Anexos possuem tabela de metadados, allowlist de MIME type, limite de 50 MiB e bucket privado com policies por tenant.
- Auditoria registra `service_request.created` e `service_request.updated`; histórico inicial de status é criado no INSERT.

### Adicionado
- `lib/features/service_requests/domain/` — `ServiceRequest`, `ServiceRequestStatus`, `ServiceRequestChannel`, `ServiceCategory`, `ServicePriority`.
- `lib/features/service_requests/data/service_request_repository.dart` — listagem paginada, filtros server-side, detalhe, criação, atualização, transição de status, categorias, prioridades e histórico.
- `lib/features/service_requests/application/` — notifiers/providers de lista, formulário, detalhe, categorias, prioridades e histórico.
- `lib/features/service_requests/presentation/` — tela de lista com busca/filtros, tela de criação, tela de detalhe e chip de status.
- Rotas `/chamados`, `/chamados/novo`, `/chamados/:id` e entrada "Chamados" no shell responsivo.
- `supabase/migrations/0003_service_requests.sql` e rollback.
- `test/service_requests/` — testes de domínio, formulário e tela de lista.
- `test/isolation/0003_rls_service_requests_test.sql` — roteiro SQL para isolamento, permissões, histórico e auditoria.

### Corrigido
- `supabase/migrations/0002_customers.sql` — removido predicado inválido com subquery no índice `idx_customers_name_trgm`; `pg_trgm` agora é criado explicitamente antes do índice.
- `validateEmail()` agora aceita domínios com subdomínios (`usuario@empresa.com.br`).
- Testes legados de Cliente atualizados para construtores de erro com parâmetros posicionais.
- `test/widget_test.dart` atualizado para o app atual com Riverpod/GoRouter.
- Limpeza de avisos do `flutter analyze` em imports, campos tipados, APIs depreciadas e uso assíncrono de `BuildContext`.

### Testes
- `flutter analyze` — sem issues.
- `flutter test` — todos os testes passaram.
- Supabase remoto `Service_Saas` vinculado e verificado: migrations `0001`, `0002`, `0003` aplicadas; tabelas de clientes/chamados, policies principais e bucket privado `service-request-attachments` confirmados.

### Operação
- Rollbacks movidos de `supabase/migrations/` para `supabase/rollbacks/` para não serem executados acidentalmente pelo Supabase CLI.
- `supabase/config.toml` atualizado com `project_id = "pkbluscdssiiumrppmwa"` (não secreto).

## [Documentação] — 2026-07-21

### Adicionado
- `docs/DELIVERY_1.md` — síntese auditável da Entrega 1 com visão, personas, jornada, escopo, MVP, fora do MVP, módulos, arquitetura, diagrama textual, STRIDE, modelo de dados, matriz de papéis, máquinas de estado, backlog, critérios de aceite, Definition of Done, riscos, plano das oito entregas, estimativas, ADRs e perguntas bloqueadoras.
- ADR-021, ADR-022 e ADR-023 em `docs/DECISIONS.md`: autenticação por e-mail/senha no MVP, MVP genérico por vertical de serviço e direção visual moderna/neomórfica com acessibilidade obrigatória.

### Alterado
- `docs/PROJECT_STATE.md` — registrada a consolidação da documentação de fundação sem alterar o estado operacional atual da Entrega 3.
- `docs/DELIVERY_1.md`, `docs/VISION.md`, `docs/ARCHITECTURE.md` e `docs/SECURITY.md` — incorporadas as respostas do usuário sobre especialidades, autenticação, modelagem, roles, isolamento, staging, estimativas e estilo visual.

## [Entrega 3] — 2026-07-21

### Segurança
- `tenant_id` **nunca aceito do cliente**: trigger `_sf_set_customer_meta()` SECURITY DEFINER força `tenant_id = current_tenant_id()` em INSERT/UPDATE na tabela `customers`, sobrescrevendo qualquer valor enviado pelo Flutter.
- Tabelas filhas (contacts, addresses, assets): trigger `_sf_set_child_customer_meta()` SECURITY INVOKER faz `SELECT tenant_id FROM customers WHERE id = NEW.customer_id` — se RLS da tabela pai negar acesso, a inserção falha automaticamente (isolamento em cascade).
- RLS habilitado em todas as 4 novas tabelas; deny-by-default; políticas explícitas via `has_permission('customers.read')` / `has_permission('customers.write')`.
- `customers`: sem política DELETE — soft-delete apenas (`is_active = false`).
- Auditoria LGPD: `_sf_audit_customer_change()` SECURITY DEFINER registra eventos `customer.created`/`customer.updated` **sem logar** `document` (CPF/CNPJ) nem `email`.
- ADR-017 decidido: valores monetários em `int` (centavos), sem biblioteca externa no MVP.
- ADR-018 decidido: testes de RLS via arquivos SQL em `test/isolation/` contra instância local Supabase CLI.

### Adicionado

**Supabase / Banco:**
- `supabase/migrations/0002_customers.sql` — tabelas `customers`, `customer_contacts`, `customer_addresses`, `customer_assets`; validação de CPF/CNPJ (regex); validação de 27 UFs brasileiras; índices únicos parciais (document×tenant, is_primary, is_default); triggers de meta + auditoria; RLS completo.
- `supabase/migrations/0002_customers_rollback.sql`.

**Domínio Flutter (`lib/features/customers/domain/`):**
- `customer.dart` — `Customer` (Freezed), `CustomerType` enum (person/company/condominium/publicEntity), `customerFromRow()`, `toInsertPayload()` (omite tenant_id).
- `customer_contact.dart` — `CustomerContact` (Freezed), builders e payload.
- `customer_address.dart` — `CustomerAddress` (Freezed), `kBrazilianStates` (27 UFs), `oneLineAddress`.
- `customer_asset.dart` — `CustomerAsset` (Freezed), `displayName` (corretamente verifica string vazia antes de concatenar).

**Dados Flutter (`lib/features/customers/data/`):**
- `customer_repository.dart` — `CustomerFilter`, `CustomerRepository.listPaged()` (paginação 20/página, heurística de total), `get`, `create`, `update`, `deactivate`, `reactivate`; CRUD completo para contatos, endereços e ativos; `_mapError()` mapeia 23505/42501.

**Aplicação Flutter (`lib/features/customers/application/`):**
- `customer_list_notifier.dart` — `CustomerListState` (items, filter, page, totalCount, isLoading, isLoadingMore, hasMore, isEmpty); `CustomerListNotifier` (load, loadMore, applyFilter, refresh, removeFromList, updateInList); providers `customerListProvider`, `customerDetailProvider`, `customerContactsProvider` (`List<CustomerContact>`), `customerAddressesProvider` (`List<CustomerAddress>`), `customerAssetsProvider` (`List<CustomerAsset>`), `customerRepositoryProvider`.
- `customer_form_notifier.dart` — sealed `CustomerFormState` (Idle/Loading/Success/Error); `CustomerFormNotifier` (createCustomer, updateCustomer, deactivateCustomer, reset); `CustomerContactFormNotifier`; `CustomerAddressFormNotifier`; strip de não-dígitos antes de persistir CPF/CNPJ/fone.

**Apresentação Flutter (`lib/features/customers/presentation/`):**
- `customer_list_screen.dart` — `ConsumerStatefulWidget`, SearchBar, FilterChips por tipo e ativo/inativo, `ListView.separated` com `_CustomerCard`, infinite scroll (ScrollController 200px do fundo → `loadMore()`), FAB → `/clientes/novo`.
- `customer_detail_screen.dart` — `TabController` 3 abas (Dados / Contatos / Endereços); AppBar com PopupMenu (editar / desativar / reativar); `_DataTab` formata CPF/CNPJ/fone; `_ContactsTab` com bottom-sheet de edição; `_AddressesTab` com tela fullscreen de endereço.
- `customer_form_screen.dart` — modo criar/editar (parâmetro `Customer?`); `SegmentedButton<CustomerType>`; campo tradeName visível somente para não-PF; validação CPF ou CNPJ conforme tipo.
- `widgets/customer_type_chip.dart` — `CustomerTypeChip` com cor e ícone por tipo via switch expression.

**Router / Shell:**
- `lib/core/router/app_router.dart` — rotas `/clientes`, `/clientes/novo`, `/clientes/:id`, `/clientes/:id/editar` (extra type-checked: `extra is Customer`).
- `lib/core/widgets/responsive_shell.dart` — destino "Clientes" adicionado à NavigationRail/Bar.

**Testes:**
- `test/customers/customer_form_notifier_test.dart` — 7 casos: estado inicial idle, create success, PermissionError, BusinessRuleError (CPF/CNPJ duplicado), update success, deactivate success, reset; testes de `CustomerType` (usesCpf, fromValue/value, unknown→ArgumentError).
- `test/isolation/0002_rls_customers_test.sql` — 12 testes SQL (T1–T12): isolamento cross-tenant, restrições por role (técnico read-only, viewer read-only), segurança de tabela filha (beta não insere contato em customer do alpha), unicidade de document, is_primary, is_default; geração de audit_log.

### Corrigido
- `UnexpectedError`, `NotFoundError`, `BusinessRuleError`, `PermissionError` usam parâmetros **posicionais** — todos os usos em `customer_repository.dart`, `customer_list_notifier.dart` e `customer_form_notifier.dart` foram corrigidos de sintaxe named (`userMessage:`) para posicional. Causa: inconsistência entre a assinatura da classe `AppError` e o código gerado na E3.

### Notas de migração para a E4
- `flutter pub run build_runner build` — obrigatório (gera `.freezed.dart`, `.g.dart`, `.mocks.dart`).
- Aplicar `0002_customers.sql` no Supabase (SQL Editor ou `supabase db push`).
- Substituir UUIDs placeholder em `test/isolation/0002_rls_customers_test.sql` pelos UUIDs reais do seed.
- `flutter test` para validar todos os testes (validators, auth, customers).

---

## [Entrega 2] — 2026-07-21

### Atualizações incrementais — 2026-07-23
- Corrigido o overflow vertical da navegação lateral no desktop: o `NavigationRail` agora rola internamente e o menu do usuário fica ancorado no rodapé do shell, evitando o erro visual de `BOTTOM OVERFLOWED`.
- O módulo `Pagamentos` saiu do placeholder e passou a ter tela operacional própria, com resumo de pendências, vencidos, liquidados, recebido e baixa manual em popup.
- O módulo `Fiscal` saiu do placeholder e passou a ter tela operacional própria, com conferência de recibos emitidos, valor documentado, pendências sem recibo e visualização/impressão do documento.
- O módulo `Promoções` saiu do placeholder e passou a ler a carteira de clientes para sugerir ofertas por perfil, com blocos de ativação comercial e segmentação inicial.

### Ajuste incremental — 2026-07-24
- O cadastro de profissional deixou de bloquear o salvamento quando o campo `Vincular ao usuário interno` estiver vazio ou quando a lista de usuários internos técnicos vier sem opções. O vínculo continua disponível como opcional e pode ser feito depois.
- A agenda passou a listar todos os profissionais ativos cadastrados, mesmo sem vínculo imediato com usuário interno. O vínculo continua sendo exigido apenas para efetivar o agendamento no horário.

### Segurança
- `main.dart` reescrito: credenciais hardcoded removidas, substituídas por `EnvConfig` com `--dart-define-from-file`.
- `.gitignore` atualizado: protege `dart_defines/*.json`, `*.env`, arquivos gerados.
- Migration com RLS `ENABLE ROW LEVEL SECURITY` em 11 tabelas; `deny by default`; políticas explícitas mínimas.
- Funções `SECURITY DEFINER` com `SET search_path = public` fixo.
- `audit_logs` com policies que bloqueiam UPDATE e DELETE.
- `AuthNotifier.sendPasswordReset`: mensagem genérica anti-enumeração de usuários.
- `AuthNotifier._mapAuthException`: mapeamento de erros Supabase sem revelar existência de usuário.

### Adicionado
**Flutter:**
- `lib/core/config/env_config.dart` — leitura segura de variáveis via `String.fromEnvironment`.
- `lib/core/theme/` — Material 3 completo (light/dark), AppColors.
- `lib/core/router/app_router.dart` — GoRouter com guard de auth e redirect para criação de empresa.
- `lib/core/widgets/responsive_shell.dart` — NavigationRail (≥600px) e NavigationBar (<600px).
- `lib/core/widgets/app_loading.dart` — SplashScreen e AppLoading.
- `lib/core/widgets/error_view.dart` — ErrorView e EmptyView.
- `lib/core/error/app_error.dart` — AppError sealed class (Auth, Permission, NotFound, Business, Network, Validation, Unexpected).
- `lib/core/utils/validators.dart` — CPF, CNPJ, CEP, e-mail, senha, telefone, slug.
- `lib/features/auth/` — AuthNotifier (Riverpod), LoginScreen, ForgotPasswordScreen, ResetPasswordScreen.
- `lib/features/tenant/` — TenantNotifier, CreateTenantScreen (chama `create_tenant_with_owner`).
- `lib/features/dashboard/` — DashboardScreen placeholder.
- `lib/shared/providers/` — supabase_provider, auth_provider (stream + user + isAuthenticated), tenant_provider (membership, tenant, role).
- `lib/main.dart` — ProviderScope + MaterialApp.router + pt-BR localizations.

**Supabase / Banco:**
- `supabase/migrations/0001_foundation.sql` — 11 tabelas, 4 triggers, 5 funções helper, RLS policies, seed de 12 roles e 24 permissions.
- `supabase/migrations/0001_foundation_rollback.sql`.
- `supabase/seed/dev_seed.sql` — 2 tenants fictícios para testes de isolamento.
- `supabase/config.toml`.

**Testes:**
- `test/auth/validators_test.dart` — 18 casos: email, senha, CPF, CNPJ, slug, CEP, telefone.
- `test/auth/auth_notifier_test.dart` — estado inicial e resetState.
- `test/widgets/login_screen_test.dart` — estrutura, validação de campos, botão desabilitado em loading.
- `test/isolation/rls_isolation_test.sql` — 6 testes de isolamento entre tenants.

**Config:**
- `dart_defines/dev.example.json`, `dart_defines/staging.example.json`.

### Alterado
- `pubspec.yaml` — removido Firebase, auto_route, get_it, injectable, provider, flutter_bloc, easy_localization, flutter_gen_runner, flutter_native_splash, flutter_launcher_icons; adicionado go_router.
- `.gitignore` — adicionada proteção de segredos (dart_defines, .env).
- `lib/app/domain/` e `lib/app/infra/` — marcados como deprecados (substituídos pela estrutura feature-first).

### Notas de migração para a E3
- Rodar `flutter pub get` para regenerar `pubspec.lock`.
- Aplicar `0001_foundation.sql` no Supabase antes de qualquer teste.
- Executar seed após criar usuários de teste no Supabase Auth.

---

## [Entrega 1] — 2026-07-21

### Adicionado
- Documentação de fundação: VISION.md, ARCHITECTURE.md, THREAT_MODEL.md, DATA_MODEL.md, SECURITY.md, ROADMAP.md, DECISIONS.md (ADR-001..016), PROJECT_STATE.md.

Sem código, migrations ou infraestrutura nesta entrega.

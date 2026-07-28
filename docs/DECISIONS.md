# ServiceFlow — Registro de Decisões (ADRs)

Formato: contexto → decisão → consequências. Status: aceita salvo indicação.

## ADR-001 — Monólito modular sobre Supabase
Microserviços adiariam o MVP sem benefício no volume atual. **Decisão:** app Flutter único + Supabase; módulos com limites lógicos. **Consequência:** extração futura possível; regras críticas concentradas no banco/Edge.

## ADR-002 — Multitenancy por linha (tenant_id + RLS) em schema único
Alternativas (schema por tenant, banco por tenant) elevam custo operacional. **Decisão:** coluna tenant_id + RLS deny-by-default; testes de isolamento obrigatórios. **Consequência:** disciplina rígida de policies; migração para sharding só se escala exigir.

## ADR-003 — Regras críticas server-side (SQL/Edge), Flutter só pré-visualiza
Cálculo de orçamento, transições de estado, numeração, conversão OS, baixas: funções SQL transacionais + Edge Functions. **Consequência:** menos lógica duplicada confiável; Flutter mantém cálculo espelho apenas para UX.

## ADR-004 — Repositório único, sem monorepo multi-app
Um app Flutter atende web+mobile. **Decisão:** `/apps/field_service_app` + `/supabase` + `/docs` no mesmo repo. Revisitar se surgir app separado (portal do cliente nativo, app do parceiro).

## ADR-005 — Links públicos: token hasheado + Edge Function, sem conta
Token CSPRNG ≥256 bits, SHA-256 no banco, expiração, escopo por versão de orçamento, OTP opcional para aprovar. **Consequência:** cliente aprova sem fricção; superfície pública limitada a Edge Functions com rate limit.

## ADR-006 — Versionamento de orçamento por snapshot imutável
Envio congela `quotation_versions` + itens. Alteração ⇒ nova versão. Aprovação referencia versão. **Consequência:** disputa "aprovei outro valor" resolvida por evidência.

## ADR-007 — Conversão orçamento→OS idempotente por constraint
`work_orders.quotation_id UNIQUE` + função transacional. Aprovações repetidas não criam duas OS.

## ADR-008 — Moeda em NUMERIC; sem float em valor monetário
NUMERIC(14,2) valores, (14,4) custos unitários, (12,3) quantidades. Dart usa tipo decimal/int em centavos na camada de domínio — definir lib na E2 (candidata: `decimal`).

## ADR-009 — PDF via Edge Function no MVP
Sem VPS até evidência de necessidade (timeout/complexidade). PDFs armazenados com checksum+versão em bucket com URL assinada. Reavaliar na F2 com métricas.

## ADR-010 — Conflito de agenda: validação em função transacional (não EXCLUDE) — *provisória*
EXCLUDE USING gist com tstzrange é elegante, mas dificulta exceções autorizadas ("dois atendimentos com autorização explícita"). **Decisão provisória:** função transacional com advisory lock por técnico + flag de override auditado. Confirmar na E5.

## ADR-011 — Fiscal: abstração apenas
Nenhum motor fiscal próprio. `FiscalProvider` no-op + registro de solicitação de emissão. Integração com provedor homologado (ex.: emissor NFS-e) na F8.

## ADR-012 — WhatsApp no MVP: deep link + registro manual
Sem API não oficial em produção. API oficial (Cloud API) na F8 atrás de `WhatsAppProvider`.

## ADR-013 — Pagamento no MVP: registro manual conciliável
Sem gateway. Maquininha registrada manualmente (NSU, bandeira, taxas, líquido). Gateway/Pix por webhook validado na F8 atrás de `PaymentProvider`.

## ADR-014 — Auditoria em tabela INSERT-only no mesmo banco
Sem SIEM no MVP. Policies impedem UPDATE/DELETE. Particionamento/exportação quando volume justificar.

## ADR-015 — platform_admin sem acesso default a dados de tenant
Suporte via fluxo break-glass: concessão temporária, escopada e auditada. Implementação mínima na F0 (flag + auditoria), fluxo completo na F2.

## ADR-016 — Estoque fora do MVP; materiais da OS sem baixa
`work_order_materials` registra consumo sem estoque na F1. Na F3, consumo passa a gerar `stock_movements`; migração de dados prevista (expand-and-contract).

**Concluído em F3-P2 (migration 0043), com uma escolha que vale registrar:**
o vínculo com o catálogo é **opcional**, não obrigatório. O técnico escolhe um
produto (baixa o saldo, custo vem do médio) ou digita texto livre (só registra
custo). Exigir catálogo travaria a conclusão da OS quando o cadastro está
incompleto ou o saldo diverge — e quem paga esse custo é quem está em campo,
sem acesso ao cadastro. `product_id` nulo identifica o caso, e
`list_work_order_materials` expõe `from_stock` para que se possa medir quanto do
consumo ficou fora do controle.

Sobre a migração de dados: os lançamentos históricos ficam com `product_id`
nulo. **Não** houve tentativa de casar descrição em texto livre com o catálogo
por similaridade — adivinhar vínculo contábil a partir de texto produziria
estoque errado com aparência de correto.

O depósito é sempre o padrão do tenant; multi-depósito na OS fica para F3-P4.

## ADR-017 — Tipo monetário em Dart: int em centavos (sem lib externa no MVP)
Contexto: ADR-008 mandatou NUMERIC no banco; a camada Dart precisa de representação segura.
Alternativas: lib `decimal`, `int` em centavos, `BigInt`, `Decimal` do package `decimal`.
**Decisão:** usar `int` (centavos) nas entidades de domínio e na camada de dados; formatação em
`NumberFormat.currency(locale:'pt_BR', symbol:'R\$')` do pacote `intl` (já em pubspec).
Não adicionar lib `decimal` até que seja comprovado que operações de divisão intermediária
no Flutter causem problema (avaliação na E6 — quotations).
**Consequências:** sem dependência extra; divisões de percentual tratadas com arredondamento
explícito (`(centavos * pct / 100).round()`); UI sempre formata a partir de int; servidor
é a fonte da verdade para todos os cálculos (ADR-003).

## ADR-018 — Testes de RLS: arquivos SQL + Supabase CLI local
Contexto: precisamos verificar isolamento entre tenants de forma automatizada sem expor banco de produção.
**Decisão:** manter arquivos `.sql` em `test/isolation/` com instruções `SET LOCAL role` e
`SET LOCAL request.jwt.claims`. Execução via `psql` contra instância Supabase CLI local
(`supabase start` → `supabase db reset` → executar scripts). CI usa `supabase/config.toml`
para subir stack local antes dos testes SQL. Testes Flutter (mockito) para camada de dados;
isolamento real somente via SQL local.
**Consequências:** cada entrega adiciona um arquivo `<n>_rls_<módulo>_test.sql`; exige
Docker na pipeline de CI; setup documentado em `docs/CI_SETUP.md` (a criar na E8).

## ADR-020 — Custo de estoque: média ponderada móvel
Contexto: F3 exige definir como valorizar saída de material antes de escrever `stock_movements`,
porque a escolha determina o schema. As três candidatas eram média ponderada móvel, PEPS/FIFO
e última compra.

**Decisão:** custo médio ponderado móvel, recalculado a cada entrada.

Descartadas:
- **Última compra** — não é aceita para inventário fiscal no Brasil; serviria só para visão
  gerencial e exigiria retrabalho quando o cliente precisasse de valoração fiscal.
- **PEPS/FIFO** — igualmente aceita e mais precisa sob validade ou preço volátil, mas exige
  camadas de custo por entrada desde o início. Complexidade não justificada para o perfil de
  material de FSM (peças e insumos, giro baixo, preço estável).

**Consequências:**
- `stock_balances` guarda `quantity` e `average_unit_cost_cents`; não há camadas por lote.
- A cada entrada: `novo_custo = (saldo_qtd * custo_atual + entrada_qtd * custo_entrada) /
  (saldo_qtd + entrada_qtd)`. A saída consome pelo custo médio vigente, sem alterá-lo.
- O cálculo roda **exclusivamente em RPC no banco** (ADR-003) — nunca no Flutter.
- Divisão com arredondamento explícito para centavos (ADR-017); o resíduo de arredondamento
  fica no saldo, não some.
- Saldo negativo é proibido: a saída que zeraria abaixo de zero é rejeitada, senão o custo
  médio perde sentido matemático.
- Se lotes/validade entrarem no F3 (P5), eles servem para **rastreabilidade**, não para
  valoração — o custo continua sendo o médio. Migrar para PEPS depois exigiria ADR novo e
  recomposição histórica dos movimentos.

## ADR-021 — Autenticação do MVP por e-mail e senha
Contexto: login social, OAuth, SAML e SSO aumentam complexidade, configuração e superfície de ataque antes da validação do fluxo operacional.
**Decisão:** MVP usa Supabase Auth com e-mail e senha, recuperação de senha e confirmação de e-mail configurável. MFA fica preparado para administradores, mas não obrigatório para todos no MVP.
**Consequências:** onboarding inicial simples e previsível; integrações de identidade corporativa ficam para fase posterior sem bloquear a fundação atual.

## ADR-022 — MVP genérico por vertical de serviço
Contexto: o produto deve atender eletricistas, hidráulica, refrigeração, informática, facilities e manutenção, mas regras específicas demais atrasariam o MVP.
**Decisão:** requisitos do MVP são genéricos de Field Service Management. Segmentos serão representados por categorias, serviços, materiais, campos descritivos e configurações por tenant, não por fluxos verticais rígidos.
**Consequências:** menor complexidade inicial; futuras especializações podem surgir por templates, catálogos ou módulos opcionais conforme validação comercial.

## ADR-023 — Direção visual moderna/neomórfica com acessibilidade obrigatória
Contexto: foi aprovada uma referência visual moderna e futurista com neomorfismo, sombras suaves, superfícies claras e acento violeta.
**Decisão:** adotar neomorfismo controlado na UI: fundo claro frio, painéis elevados, botões suaves, microinterações e animações curtas. Em telas operacionais, densidade, legibilidade, contraste, foco de teclado e estados claros têm prioridade sobre efeito visual.
**Consequências:** identidade visual distinta sem sacrificar uso diário; componentes devem ser testados em desktop/mobile e com contraste adequado.

## ADR-024 — Rastreabilidade por lote/série opcional por produto
Contexto: a maioria dos produtos de FSM (parafuso, cabo, conector) não precisa de rastreio individual; só peças com garantia, regulação ou identidade única (compressor, placa, bateria) precisam saber exatamente qual unidade/lote foi para qual OS e cliente.
**Decisão:** campo `tracking_type` no produto (`none` | `lot` | `serial`), opcional e por produto — não um flag global nem obrigatório para todo `track_stock`. Um produto rastreado escolhe **um** dos dois tipos, não os dois ao mesmo tempo: `lot` para consumíveis com lote de fabricação compartilhado, `serial` para equipamentos com identidade individual (nesse caso, cada movimento fica limitado a quantidade = 1). Lotes/séries são identificados por um código de texto livre (não numérico sequencial), criados sob demanda (find-or-create) na primeira entrada que os referencia. Sem data de validade nesta entrega — é só identificação e rastreabilidade (qual lote/série saiu em qual OS), não controle de vencimento; validade fica para quando houver necessidade real comprovada (YAGNI).
**Escopo excluído desta entrega:** transferências entre depósitos (`transfer_stock`) não carregam lote/série — ela insere direto em `stock_movements` para preservar conservação exata de valor (ADR-020) e estender isso exigiria replicar a granularidade de lote também em `stock_transfers`/`stock_transfer_items`, aumento de escopo não pedido. Inventário cíclico (`stock_counts`) também não conta por lote — ajusta o agregado do produto, não lotes individuais. Ambos ficam registrados como lacuna conhecida, não como bug.
**Consequências:** rastreabilidade real (histórico de um lote/série específico) sem redesenhar o modelo de custo médio ponderado por produto — o saldo continua agregado por produto+depósito; lote/série é uma camada de identificação sobre os movimentos, não uma segunda contabilidade de custo paralela.

## ADR-025 — Contas a pagar: geração automática no recebimento, baixa manual simples
Contexto: a migration 0044 (F3-P3) já deixou registrado que o pedido de compra recebido não gera conta a pagar — o custo entra no estoque, mas o compromisso financeiro fica fora do sistema, dependendo do financeiro lembrar de lançar manualmente. `receivables`/`payment_records` (E8, já em produção) resolvem o lado de receber com baixa manual simples, sem conceito de conta bancária/caixa.
**Decisão:** `payables` nasce com **criação automática dentro da mesma transação de `receive_purchase_order`** — cada recebimento (total ou parcial) gera a conta a pagar correspondente ao valor recebido, com FK para `purchase_orders`/`purchase_order_items`. Igual a `receivables`, o pagamento (`payable_payments`) é **baixa manual simples**: method livre (pix/transferência/boleto/dinheiro/etc), sem `financial_accounts` (contas bancárias/caixa) nesta entrega — o modelo espelha `receivables`/`payment_records` de propósito, para manter consistência com o que já está em produção em vez de introduzir um segundo padrão.
**Consequências:** fecha a lacuna que motivou o pedido de F4 (compromisso financeiro nunca mais fica "fora do sistema" por esquecimento) sem redesenhar nem migrar dados de `receivables`/`payment_records`, que continuam como estão. `financial_accounts`/conciliação bancária ficam para uma entrega futura de F4, quando houver necessidade real de reconciliar contra extrato (YAGNI) — layout do plano de contas (`chart_of_accounts`) e centro de custo (`cost_centers`) também ficam fora desta primeira entrega, registrados como pendentes abaixo.

## ADR-026 — DRE simples em regime de caixa, sem plano de contas
Contexto: `receivables`/`payment_records` (E8) e `payables`/`payable_payments` (F4-P1) já registram tudo que entra e sai de caixa. Um DRE por competência, com CMV alocado por venda e plano de contas, é um projeto grande — mas boa parte do valor de "ver o resultado do mês" já dá para tirar do que existe, sem esperar `financial_accounts`/`chart_of_accounts`.
**Decisão:** `get_dre_monthly(p_year)` agrega, por mês, receita = soma de `payment_records.amount_cents` (o que o cliente efetivamente pagou) e despesa = soma de `payable_payments.amount_cents` (o que foi efetivamente pago a fornecedores); resultado = receita − despesa. É **regime de caixa** (quando o dinheiro mudou de mão), não competência (quando a venda/compra aconteceu) — meses sem nenhum pagamento simplesmente não aparecem, não são zero-preenchidos. Não tenta ratear CMV por venda individual, não usa plano de contas nem centro de custo: é a fotografia mais simples que já é verdade com os dados que existem hoje.
**Consequências:** relatório útil imediatamente, sem nenhuma tabela nova (só uma função de leitura sobre `payment_records`/`payable_payments`, ambas já com RLS). Limitação conhecida e aceita: não reflete competência (uma venda fechada em dezembro e paga em janeiro aparece em janeiro), não separa custo fixo de variável, não mostra CMV por produto. Migrar para DRE por competência com plano de contas fica para quando houver demanda real validada (YAGNI) — registrado abaixo.

## ADR-028 — Agenda identifica profissional, não usuário do sistema
Contexto: `service_professionals` (0018) nasceu com `linked_user_id` opcional e o comentário da coluna já dizia o resto — "quando preenchido, o profissional pode receber agenda". Na prática, parceiro externo sem login nunca foi agendável: `appointment_assignments.technician_user_id` era `NOT NULL REFERENCES profiles(id)` e `schedule_appointment` exigia membership ativa com papel `technician`. A tela de profissionais permite cadastrar parceiro, e quem cadastra espera agendá-lo — o arrasto respondia "Fulano não tem usuário vinculado, agende pelo formulário", e o formulário dizia a mesma coisa. Não havia caminho nenhum.
**Decisão:** `appointment_assignments` passa a apontar para `professional_id`, com `technician_user_id` opcional e preenchido só quando existe usuário vinculado. Quem tem login continua ganhando o vínculo com `profiles` (e portanto acesso ao próprio atendimento no app de campo); quem não tem entra na agenda do mesmo jeito, só não enxerga o app. Conflito de horário passa a ser avaliado por profissional, via `_sf_professional_busy`. A alternativa — criar usuário "fantasma" em `profiles` para cada parceiro — foi recusada: seria mais barata no curto prazo, mas polui a tabela de identidade com linhas que nunca autenticam e faz RLS por `auth.uid()` mentir. Agenda e identidade são coisas diferentes.
**Consequências:** parceiro externo entra na fila, é arrastado para o horário e conta como profissional do atendimento, inclusive como segundo profissional (ADR-027). `technical_visits.technician_id` fica nulo nesses casos — a coluna já era nullable. Limitação aceita: parceiro sem login **não cancela o próprio atendimento**, porque a checagem de "sou o técnico atribuído" é por `auth.uid()`; sem app, o cancelamento dele passa pelo operador. `schedule_appointment` mudou de assinatura (ganhou `p_professional_id`), então a versão anterior é derrubada na mesma migration — dois overloads no catálogo deixariam a chamada ambígua e o PostgREST devolveria PGRST203.

## A registrar nas próximas entregas
- ADR-019: motor de PDF (lib Dart em Edge/Deno vs serviço) (E6).
- F5-P2: UI para atribuir mais de um profissional ao mesmo atendimento (o schema já suporta via `appointment_assignments`); relatórios de BI sobre `appointment_events` (produtividade por técnico, taxa e motivo de cancelamento, tempo entre abertura e agendamento).
- F4-P3+: `financial_accounts` (contas bancárias/caixa) e como `receivables`/`payment_records`/`payables` passam a se ligar a elas; `bank_reconciliation` (formato de importação de extrato); `chart_of_accounts` e `cost_centers`; `financial_transactions` como possível livro-razão único; DRE por competência com CMV alocado por venda (a partir de `stock_movements`/ADR-020, sem duplicar lógica de custo).

## ADR-027 — Agenda por fila de categoria, com histórico próprio de agendamento
Contexto: a agenda era um calendário passivo — o operador abria um horário vazio e preenchia um formulário escolhendo cliente, chamado e técnico. Não havia nenhuma noção de "trabalho aguardando alguém". O pedido de F5 inverte isso: chamados e OS aprovadas formam uma fila visível para todos os profissionais da categoria correspondente, o operador arrasta o item para um horário, e cancelar devolve o item para a fila de todos.
**Decisão:** a fila é **derivada, não materializada** — não existe tabela `queue`. Um item está na fila quando não tem `appointment` com status diferente de `cancelled`. Isso torna "sumir da fila dos outros ao agendar" e "voltar para a fila ao cancelar" consequências automáticas do estado dos agendamentos, sem sincronização entre duas fontes de verdade. A categoria do item vem do chamado; a OS **herda** a categoria do chamado de origem (`work_orders.request_id`), em vez de ganhar coluna própria — OS avulsa, sem chamado, não tem categoria e aparece para todas. O histórico vai para `appointment_events`, tabela append-only alimentada por **trigger** em `appointments` (não pela aplicação), com índice por técnico + tipo de evento + data, pensado para as perguntas de BI de produtividade e cancelamento.
**Consequências:** dois defeitos pré-existentes precisaram ser corrigidos junto, porque a fila os expõe: (1) `appointments.reference_id` tinha FK rígida para `service_requests` mesmo quando `kind = 'work_order'`, tornando o agendamento de OS impossível no banco — a FK virou validação por tipo no trigger de meta; (2) `schedule_appointment` recusava `p_kind <> 'visit'` com "ainda não suportado no MVP", embora a UI já oferecesse "Agendar OS" há várias entregas. Limitação conhecida: profissional parceiro sem `linked_user_id` não recebe por arrasto, porque `schedule_appointment` exige um técnico com membership ativa — a UI avisa e manda usar o formulário. Múltiplos profissionais no mesmo atendimento já são suportados pelo schema (`appointment_assignments` é 1:N), mas a UI ainda atribui um só; fica registrado abaixo.

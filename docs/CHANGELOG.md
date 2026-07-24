# Changelog

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

# ServiceFlow — Estado do Projeto

**Última atualização:** 2026-07-27 · **Entrega atual concluída:** F4-P2 (DRE simples em regime de caixa, ADR-026) · **F4-P1/P2 concluídas** · **F3 completo (P1–P5)** · **F2 completo (P1–P5)** · **RLS validado em banco real** · **Próxima:** bloqueadores MVP restantes (deploy em staging, pausado a pedido do usuário) ou seguir F4-P3+ (contas bancárias, conciliação, plano de contas)

> ✅ **Validação RLS concluída em 2026-07-27.** Migrations 0001–0046 aplicadas no Supabase remoto (`pkbluscdssiiumrppmwa`) via `supabase db push`. 18/18 testes automatizados de `test/isolation/` (0002–0020, exceto 0006 manual) passando contra o banco real — relatório em `test_results_isolation_2026-07-27_011114.txt`. Faltam só os 2 manuais (`0006_public_quotation_link_test.sql`, `rls_isolation_test.sql`).
>
> A primeira execução real encontrou e corrigiu **6 bugs nunca detectáveis sem banco real**: (1) `create_test_users.sh` incompatível com bash 3.2 do macOS (`declare -A`) e um `pipefail`+`grep` que matava o script em silêncio; (2) `:'VAR'` do psql não interpola de forma confiável dentro de `DO $$...$$` — `apply_test_uuids.sh` agora substitui literal no corpo; (3) `WHEN SQLSTATE 'P0001' AND SQLERRM = ...` é sintaxe inválida em PL/pgSQL (replicado nos 18 arquivos de teste); (4) setup de teste inserindo direto sem simular o usuário dono do tenant — o trigger de `tenant_id` corretamente rejeitava; (5) três testes com expectativa errada sobre exceções de RLS (UPDATE filtrado por RLS não lança exceção, só zera `ROW_COUNT`) e claim JWT residual ao simular `anon`; (6) **bug de produção real**: `add_work_order_material` (0043/0045) passava o jsonb de auditoria no argumento errado de `log_audit` (`after_data` em vez de `metadata`) — corrigido em `0046_fix_material_audit_metadata.sql`, sem mudança de aridade.
>
> Bloqueador restante do MVP: `flutter analyze`/build/deploy em staging ainda não executados (ambiente sem Flutter SDK).

## Status

| Item | Estado |
|---|---|
| Fase | F0 concluída; F1 (RLS) e F2 (staging) preparadas e documentadas, execução real pendente do usuário |
| Código Flutter | ✅ features/customers + features/service_requests + features/scheduling + features/professionals + features/quotations + features/work_orders + features/financials + features/reports + features/settings + features/modules + features/promotions |
| Migrations | 🔄 **0001 a 0050 aplicadas no Supabase remoto em 2026-07-27; `0051`, `0052` e `0053_schedule_partner_professionals` criadas e ainda NAO aplicadas** (agenda por fila — histórico `appointment_events`, `cancel_appointment`, e correção do agendamento de OS que era impossível pela FK de `reference_id`). via `supabase db push` (0047 lote/série, 0048 contas a pagar, 0049 DRE, 0050 correção do bug de `created_at`). |
| Rollbacks | ✅ Cobertura 1:1 mantida — rollbacks de `0051`, `0052` e `0053` criados junto com as migrations (**atenção: derruba o histórico da agenda e a FK de `reference_id` não volta se já houver agendamento de OS**). **Lacuna fechada em 2026-07-26**: criados os pares faltantes de 0036–0040; 0041 corrigido para restaurar `seed_default_message_templates`; 0042 criado junto com a migration. Cobertura 1:1 com as migrations. Ordem inversa obrigatória e riscos documentados em `supabase/rollbacks/README.md` — em especial, **reverter 0039 reintroduz a falha de permissão em cancelamentos**. Nenhum rollback foi executado (sem PostgreSQL no ambiente de análise). |
| Endpoints anônimos | ⚠️ Dois em produção: `decide_public_quotation` (0006) e `submit_public_satisfaction` (0041). Inventário e riscos residuais em `docs/THREAT_MODEL.md` § "Endpoints anônimos". Rate limit por IP **não implementado** em nenhum dos dois — reavaliar antes do GA. |
| Ambientes | ⏳ Requer `dart_defines/dev.json` com credenciais reais (arquivo local, fora do Git) |
| Build runner | ⏳ Executado localmente pelo usuário quando necessário (sem Flutter SDK neste sandbox). |
| `flutter analyze` | ✅ **Executado pelo usuário em 2026-07-27 — 0 erros, 0 warnings reais.** 5 lints corrigidos (3 imports não usados, 2 identificadores locais com underscore). Restam 8 infos de API deprecated (`withOpacity`, `surfaceVariant`, `value` em `DropdownButtonFormField`) — cosmético, não bloqueia, corrigir na próxima atualização de Flutter. |
| Testes Flutter | ✅ **`flutter test` — 221 testes passando (2026-07-27).** ⏳ F3-P5 adicionou testes de domínio (`ProductTrackingType`, `lot_id`/`lot_code` em `stockMovementFromRow`) em `test/stock/stock_domain_test.dart`; F4-P1 adicionou `test/financials/payable_domain_test.dart`; F4-P2 adicionou `test/financials/dre_month_domain_test.dart` — nenhum reexecutado ainda (sem Flutter SDK no ambiente de análise). |
| Testes SQL | ✅ **21/21 executados e passando contra banco real em 2026-07-27** (`test/isolation/` 0002–0023, menos o 0006 manual). `0017` razão de estoque; `0018` consumo pela OS com atomicidade; `0019` ciclo de compra e custo da nota no médio; `0020` conservação de valor na transferência e inventário cíclico; `0021` lote/série (achou e validou a correção do bug de `created_at`/0050); `0022` contas a pagar automáticas; `0023` DRE simples; `0024` rastreabilidade da agenda e `0025` múltiplos profissionais e `0026` parceiro sem usuário (**escritos, ainda não executados — dependem de aplicar 0051-0053; o 0025 exige DOIS técnicos ativos no seed**); `0014` T3/T4 são regressão da falha corrigida em 0039. `0006` (link público de orçamento) e `rls_isolation_test.sql` seguem manuais. Runbook em `docs/FASE1_RUNBOOK_SEGURANCA_RLS.md`. |
| Migrations | ✅ **0054–0060 aplicadas em 2026-07-28** (0054–0058 via `supabase db push`; 0059–0060 via SQL Editor com o consolidado em `dist/pendentes_0059_0060.sql`). Verificado no banco: 4 tabelas (`material_categories`, `supplier_categories`, `supplier_products`, `supplier_price_history`) e 3 funções (`best_price_for_product`, `seed_material_categories`, `import_supplier_prices`). ⚠️ **0059 e 0060 não estão registradas no histórico de migrations do Supabase** — foram aplicadas fora do `db push`. Um `db push` futuro vai tentar reaplicá-las; ambas são idempotentes desde a correção das policies, então é inócuo, mas convém marcar como aplicadas (`supabase migration repair --status applied 0059 0060`). ⏳ Testes de isolamento `0027`–`0031` escritos e ainda não executados. |
| Documentação | ✅ Fundação, manuais de reconstrução, SQL, deploy, release, convites, estado do projeto e relatório técnico de auditoria (2026-07-24) atualizados |
| Git | ✅ **Resolvido em 2026-07-24**: `.git/index.lock` era um lock órfão no mount FUSE do diretório de trabalho (não removível por `rm`, mas contornável por `mv` no mesmo diretório). Todo o trabalho de E4 até F2 (156 mudanças pendentes) foi dividido em 28 commits lógicos e coesos por feature/migration/docs. `git status` limpo. |
| PII / dados sensíveis | ⚠️ **Achado em 2026-07-24**: `scripts/import_customers_eletroceu_20260722.sql` e `docs/imports/clientes_vcf_preview_2026-07-23.csv` continham dados reais de clientes (nome, CPF, e-mail, telefone, endereço) de um tenant real. Ambos foram **excluídos do Git** e adicionados ao `.gitignore`. Arquivos permanecem no disco local, fora do controle de versão. |
| Deploy | 🔄 **Em andamento — 2026-07-27.** Domínio definido: `https://serviceflow.leonardoperescouto.com` (antes `cliente.`) — falta apontar o subdomínio e atualizar Site URL/Redirect URLs no Supabase. RLS revalidada (21/21) contra o banco com 0047-0050 aplicadas. Próximo passo: refazer o build (`dist/serviceflow-staging.zip` antigo, commit `73a7d85`, está desatualizado — não tem F3-P5/F4-P1/F4-P2). Bloqueio anterior ainda não resolvido: Hostinger serviu um app antigo diferente ("clinic_mobile") na última tentativa — causa raiz não diagnosticada, a checar na republicação. Runbook em `docs/FASE2_RUNBOOK_STAGING.md`. |

## Estrutura do repositório

```
serviceflow/
  lib/
    main.dart
    core/
      config/env_config.dart
      theme/                         — Material 3, AppColors
      router/app_router.dart         — GoRouter + rotas /clientes, /chamados, /agenda, /orcamentos, /ordens-servico, /financeiro e /relatorios
      widgets/                       — responsive_shell (+ nav Clientes, Chamados, Agenda, Orçamentos, OS, Financeiro, Relatórios), app_loading, error_view, neomorphic
      error/app_error.dart
      utils/validators.dart          — CPF, CNPJ, CEP, e-mail, senha, slug, fone
    features/
      auth/                          — login, forgot_password, reset_password + AuthNotifier
      tenant/                        — create_tenant_screen + TenantNotifier
      dashboard/                     — DashboardScreen (placeholder)
      customers/
        domain/
          customer.dart              — Customer (Freezed) + CustomerType enum
          customer_contact.dart      — CustomerContact (Freezed)
          customer_address.dart      — CustomerAddress (Freezed) + kBrazilianStates
          customer_asset.dart        — CustomerAsset (Freezed)
        data/
          customer_repository.dart   — CRUD + listPaged + getContacts/getAddresses/getAssets
        application/
          customer_list_notifier.dart  — CustomerListNotifier + providers (detail, contacts, addresses, assets)
          customer_form_notifier.dart  — CustomerFormNotifier + ContactFormNotifier + AddressFormNotifier
        presentation/
          customer_list_screen.dart    — lista com busca + filtros tipo/ativo + infinite scroll
          customer_detail_screen.dart  — tabs: Dados | Contatos | Endereços
          customer_form_screen.dart    — criar/editar cliente
          widgets/customer_type_chip.dart
      service_requests/
        domain/                    — ServiceRequest, ServiceCategory, ServicePriority
        data/                      — ServiceRequestRepository + filtros server-side
        application/               — list/form notifiers + providers
        presentation/              — lista, detalhe, criação, status chip
      scheduling/
        domain/                    — Appointment, Technician e regras de período
        data/                      — AppointmentRepository + RPCs de agenda
        application/               — list/form notifiers + providers
        presentation/              — calendário mensal, agenda diária por profissional, popup de agendamento, detalhe e criação de agendamento
      professionals/
        domain/                    — ServiceProfessional e TechnicianUserOption
        data/                      — ServiceProfessionalRepository
        application/               — list notifier + providers
        presentation/              — lista neomórfica, filtros e popup de cadastro/edição
      quotations/
        domain/                    — Quotation, itens, status, decisão pública e cálculo em centavos
        data/                      — QuotationRepository + RPCs create_quotation/link público/decisão pública
        application/               — list/form notifiers + providers
        presentation/              — lista, detalhe com PDF/link público, criação em popup e tela pública de aprovação
        pdf/                       — gerador de PDF de orçamento com fonte Roboto embutida
      work_orders/
        domain/                    — WorkOrder e status de execução
        data/                      — WorkOrderRepository + RPCs converter orçamento/transicionar status
        application/               — list notifier + providers
        presentation/              — lista, criação em popup, detalhe e chip de status
      financials/
        domain/                    — Receivable, Receipt e status financeiro
        data/                      — FinancialRepository + RPCs de recebível/pagamento
        application/               — list notifier + providers
        presentation/              — tela financeira e popup de baixa manual
        pdf/                       — gerador de PDF de recibo
      reports/
        domain/                    — ReportsSnapshot com indicadores gerenciais
        data/                      — ReportsRepository agregando dados existentes com RLS
        application/               — ReportsNotifier + providers
        presentation/              — tela Relatórios neomórfica
    shared/providers/                — supabase, auth, tenant providers (Riverpod)
  scripts/
    build_staging.sh                 — build web otimizado + pacote zip para staging
    smoke_web.sh                     — smoke test HTTP para localhost ou URL publicada
    release_check.sh                 — análise + testes críticos + build + smoke local
    write_release_manifest.sh        — manifesto SHA-256 do pacote publicado
    security_preflight.sh            — segredos, pacote, rollbacks e migrations remotas
  dist/
    serviceflow-local-preview.zip    — pacote local gerado para prévia/upload manual
    serviceflow-staging-dry-run.zip  — pacote staging simulado com credenciais dev
    serviceflow-staging-dry-run.manifest.txt — manifesto do pacote staging simulado
  supabase/
    migrations/
      0001_foundation.sql            — 11 tabelas identidade/tenancy, RLS, funções, seed roles/permissions
      0002_customers.sql             — customers, contacts, addresses, assets; triggers; auditoria; RLS
      0003_service_requests.sql      — categorias, prioridades, chamados, histórico, anexos, notas, atribuições, Storage policies
      0004_scheduling.sql           — agenda, atribuições, visitas técnicas, evidências e RPC de agendamento
      0005_quotations.sql           — orçamentos, versões, itens, links públicos, aprovações e cálculo server-side
      0006_quotation_public_flow.sql — geração de link público, visualização pública e decisão pública
      0007_quotation_public_revoke.sql — revogação manual de links públicos ativos
      0008_work_orders.sql          — OS, itens, eventos, evidências e conversão de orçamento aprovado
      0009_work_order_execution.sql — horas trabalhadas e materiais aplicados na OS
      0010_work_order_acceptance.sql — aceite básico do cliente na OS
      0011_work_order_expenses.sql — despesas operacionais da OS
      0012_work_order_evidence_storage.sql — Storage privado e registro auditado de evidências da OS
      0013_financials_minimum.sql — recebíveis, pagamentos manuais e recibos
      0014_customer_satisfaction.sql — pesquisa de satisfação simples da OS
      0018_service_professionals.sql — cadastro formal de profissionais/parceiros e integração com agenda
    rollbacks/
      0001_foundation_rollback.sql
      0002_customers_rollback.sql
      0003_service_requests_rollback.sql
      0004_scheduling_rollback.sql
      0005_quotations_rollback.sql
      0006_quotation_public_flow_rollback.sql
      0007_quotation_public_revoke_rollback.sql
      0008_work_orders_rollback.sql
      0009_work_order_execution_rollback.sql
      0010_work_order_acceptance_rollback.sql
      0011_work_order_expenses_rollback.sql
      0012_work_order_evidence_storage_rollback.sql
      0013_financials_minimum_rollback.sql
      0014_customer_satisfaction_rollback.sql
    seed/dev_seed.sql                — 2 tenants fictícios (substituir UUIDs reais)
    config.toml
  dart_defines/
    dev.example.json
    staging.example.json
  docs/
    DOCS_INDEX.md                    — índice da documentação principal
    SYSTEM_MANUAL.md                 — manual funcional e operacional do sistema
    SQL_MANUAL.md                    — manual SQL/Supabase para reconstrução e segurança
    RECREATE_PROMPT.md               — prompt mestre para recriar o ServiceFlow do zero
    DEPLOY_STAGING.md                — guia de publicação staging/Hostinger
    MVP_RELEASE_CHECK.md             — checklist do release MVP
    RELEASE_NOTES_MVP.md             — notas de release
    DELIVERY_1.md                    — fundação de produto, arquitetura e escopo
    demais docs                      — arquitetura, modelo de dados, decisões, segurança e roadmap
  test/
    auth/validators_test.dart
    auth/auth_notifier_test.dart
    customers/customer_form_notifier_test.dart
    isolation/rls_isolation_test.sql
    isolation/0002_rls_customers_test.sql
    isolation/0003_rls_service_requests_test.sql
    isolation/0004_rls_scheduling_test.sql
    isolation/0005_rls_quotations_test.sql
    isolation/0006_public_quotation_link_test.sql
    isolation/0007_work_orders_test.sql
    isolation/0008_work_order_execution_test.sql
    isolation/0009_work_order_acceptance_test.sql
    isolation/0010_work_order_expenses_test.sql
    isolation/0011_work_order_evidence_storage_test.sql
    isolation/0012_financials_minimum_test.sql
    isolation/0013_customer_satisfaction_test.sql
    quotations/
    reports/
    scheduling/
    work_orders/
    widgets/login_screen_test.dart
```

## Próximos passos obrigatórios (para continuar Entrega 8)

1. **Credenciais**: copiar `dart_defines/dev.example.json` → `dart_defines/dev.json` e preencher.
2. **Migrations**: `0001` a `0013` já foram aplicadas no Supabase remoto `Service_Saas` (`pkbluscdssiiumrppmwa`).
3. **Seed**: criar usuários de teste no Supabase Auth, incluindo técnico ativo; atualizar UUIDs em `dev_seed.sql`; executar seed.
4. **`flutter pub get`**: gera `pubspec.lock` atualizado.
5. **`flutter pub run build_runner build`**: gera `*.freezed.dart` e `*.g.dart` para os modelos de domínio.
6. **Commit**: `git add -A && git commit -m "feat: ordens de servico"`.
7. **Release check local**: `./scripts/release_check.sh dart_defines/dev.json 8091` — passou nesta sessão.
7.1. **Security preflight**: `./scripts/security_preflight.sh dist/serviceflow-staging-dry-run.zip --remote` — passou nesta sessão.
8. **Testes SQL isolamento**: executar os scripts `0003`, `0004`, `0005`, `0006_public_quotation_link_test.sql`, `0007_work_orders_test.sql`, `0008_work_order_execution_test.sql`, `0009_work_order_acceptance_test.sql`, `0010_work_order_expenses_test.sql`, `0011_work_order_evidence_storage_test.sql` e `0012_financials_minimum_test.sql` após criar/confirmar usuários reais e substituir UUIDs.
9. **Migration nova**: aplicar `0018_service_professionals.sql` no Supabase remoto antes de usar a área `Profissionais` e os filtros reais da agenda.
10. **Backfill operacional**: revisar os profissionais internos importados pela migration, ajustar categoria/especialidade e cadastrar parceiros externos.
11. **Verificação manual**: criar cliente/chamado/orçamento por popup, aprovar orçamento, converter em OS, iniciar execução, registrar horas, adicionar material, registrar despesa, anexar evidência, registrar aceite com assinatura, gerar cobrança, registrar pagamento e conferir auditoria em `audit_logs`.

## Documentação de fundação

`docs/DELIVERY_1.md` consolida a Entrega 1: visão, personas, jornada, escopo, MVP,
fora do MVP, módulos, arquitetura, diagrama textual, STRIDE, modelo de dados,
RBAC, máquinas de estado, backlog, critérios de aceite, Definition of Done,
riscos, plano das oito entregas, estimativas, ADRs e perguntas bloqueadoras.
Premissas confirmadas pelo usuário: requisitos genéricos por vertical, login por e-mail
e senha, modelo de dados profundo apenas para MVP/fundação, roles iniciais sem expansão,
isolamento reforçado além de RLS, staging como critério da Entrega 8/MVP e direção visual
moderna/futurista com neomorfismo acessível.

## Manuais de reconstrução

Criados para permitir recriar o sistema inteiro caso seja necessario:

- `docs/DOCS_INDEX.md` — caminho de leitura dos documentos.
- `docs/SYSTEM_MANUAL.md` — manual funcional, operacional e visual.
- `docs/SQL_MANUAL.md` — manual de banco, migrations, RLS, Storage e validacoes.
- `docs/RECREATE_PROMPT.md` — prompt mestre para outro agente reconstruir o produto.

Regra: sempre que houver nova fase, migration, tela, fluxo, permissao, script ou regra de deploy, atualizar esses manuais junto com `docs/PROJECT_STATE.md` e `docs/CHANGELOG.md`.

## F2 — Profissionais formais

Implementado: cadastro dedicado de profissionais e parceiros com categoria explícita, status ativo/inativo e vínculo opcional com usuário interno. A agenda diária agora usa esse cadastro como fonte oficial para filtros e nomes dos profissionais, eliminando a heurística por nome.

Pendente desta trilha: reutilizar o mesmo cadastro nas linhas de orçamento e OS, no planejamento de roteiro e no apontamento de execução por parceiro.

## F2 — Convites, onboarding e assinatura

Implementado:

- Convites de membros agora geram link de aceite dedicado em `/aceitar-convite`.
- Usuário novo pode abrir o link, visualizar a empresa/papel do convite, criar senha e entrar direto no tenant.
- Usuário existente continua podendo aceitar o convite pelo login.
- O app agora bloqueia a operação quando o trial já venceu ou a assinatura está `past_due`/`canceled`.
- Quando houver bloqueio comercial, apenas a tela de regularização e `Configurações` permanecem liberadas; módulos operacionais redirecionam para a tela de assinatura.
- O link público de orçamento continua acessível mesmo quando o usuário estiver logado em tenant com bloqueio comercial.
- Após criar a empresa, o owner/admin agora é obrigado a confirmar o plano inicial em um onboarding comercial dedicado antes de entrar na operação.
- Nova migration `0029_plan_selection_onboarding.sql` adiciona `plan_selected_at` e a RPC `complete_current_tenant_plan_selection(...)`.
- Nova migration `0030_tenant_billing_history.sql` cria a linha do tempo comercial `tenant_billing_events`.
- `Configurações` agora exibe histórico comercial da assinatura e permite atualizar manualmente o status para `trialing`, `active`, `past_due` ou `canceled`.
- As mudanças de plano e de status passam a gerar eventos comerciais persistidos, preparando integração futura com gateway.

Pendente desta trilha:

- integrar cobrança real/checkout para mudança de status comercial sem ajuste manual;
- integrar gateway real para atualizar a assinatura automaticamente a partir do checkout;
- evoluir os hubs de `Pagamentos`, `Fiscal`, `Promoções`, `Campanhas`, `BI avançado` e `IA` para fluxos operacionais completos.

## F2 — Hubs iniciais dos módulos premium

Implementado:

- Novas rotas para `Pagamentos`, `Fiscal`, `Promoções`, `Campanhas`, `BI avançado` e `IA`.
- Menu principal condicionado ao plano agora expõe esses módulos quando a assinatura libera a feature.
- Dashboard passou a oferecer atalhos rápidos para os novos módulos premium.
- Cada módulo abre uma tela-base neomórfica com resumo do escopo atual e próximos incrementos planejados.
- `Pagamentos` evoluiu de tela-base para módulo operacional inicial, exibindo cobranças que pedem ação, totais de liquidação e baixa manual reaproveitando o financeiro existente.
- `Fiscal` evoluiu de tela-base para módulo operacional inicial, exibindo recibos emitidos, valor documentado, pendências documentais e acesso ao PDF do documento emitido.
- A navegação lateral desktop foi ajustada com rolagem interna para suportar todos os módulos do plano Enterprise sem estourar a altura da viewport.

Pendente desta trilha:

- transformar cada hub em módulo operacional completo, começando por `Pagamentos` e `Fiscal`;
- integrar campanhas e promoções ao funil comercial e aos orçamentos;
- expandir `BI avançado` e `IA` com dados reais, automações e análises executivas.

## Entrega 4 — Chamados

Implementado: `service_requests`, `service_categories`, `service_priorities`, histórico de status, anexos (tabela + bucket/policies Storage), notas, atribuições, filtros server-side, lista, criação, detalhe, rotas e testes Flutter.

Aplicado no Supabase remoto existente. Histórico de migrations remoto reparado para `0001`, `0002` e `0003`. Rollbacks foram movidos para `supabase/rollbacks/` para evitar que `supabase db push` tente executá-los como migrations.

## Entrega 5 — Agenda e visitas

Implementado: `appointments`, `appointment_assignments`, `technical_visits`, `visit_evidence`, RPC `schedule_appointment`, RPC `list_tenant_technicians`, bloqueio transacional de conflito por técnico, calendário mensal, popup de agendamento por data, criação de visita a partir de chamado, detalhe do agendamento, rotas e testes Flutter.

Aplicado no Supabase remoto existente. Histórico de migrations remoto reparado para `0001`, `0002`, `0003` e `0004`.

## Entrega 6 — Orçamentos (link público implementado)

Implementado: `quotations`, `quotation_versions`, `quotation_items`, `quotation_public_links`, `quotation_approvals`, RPC `create_quotation`, RPC `create_quotation_public_link`, RPC `get_public_quotation`, RPC `decide_public_quotation`, RPC `revoke_quotation_public_links`, cálculo server-side em centavos, lista, criação em popup, detalhe com geração de PDF, cópia e revogação de link público, tela pública de aprovação/rejeição, rotas, menu "Orçamentos" e testes Flutter.

Aplicado no Supabase remoto existente. Histórico de migrations remoto reparado para `0001`, `0002`, `0003`, `0004`, `0005`, `0006` e `0007`.

Pendente para fechar E6: executar o teste SQL específico do link com usuários reais.

## Entrega 7 — OS e execução (base concluída)

Implementado: `work_orders`, `work_order_items`, `work_order_events`, `work_order_evidence`, `work_order_time_entries`, `work_order_materials`, `work_order_acceptances`, `work_order_expenses`, bucket privado `work-order-evidence`, RPC `convert_approved_quotation_to_work_order`, RPC `transition_work_order`, RPC `record_work_order_time_entry`, RPC `add_work_order_material`, RPC `record_work_order_acceptance`, RPC `add_work_order_expense`, RPC `record_work_order_evidence`, lista de OS, criação em popup, detalhe com ações de execução/conclusão/horas/materiais/despesas/evidências/aceite com assinatura, rotas, menu "OS" e testes Flutter da lista/detalhe.

Aplicado no Supabase remoto existente. Histórico de migrations remoto reparado para `0001` a `0012`.

Pendente para fechar E7: execução do teste SQL com usuários reais e revisão operacional ponta a ponta.

## Entrega 8 — Financeiro mínimo + deploy (em andamento)

Implementado: `receivables`, `payment_records`, `receipts`, RPC `create_receivable_from_work_order`, RPC `register_manual_payment`, menu "Financeiro", tela financeira com resumo, lista de recebíveis, popup de baixa manual, botão "Gerar cobrança" no detalhe da OS, botão "Visualizar recibo", PDF de recibo, dashboard mínimo com indicadores financeiros, script de build staging, pacote `.zip`, manifesto SHA-256, release notes, smoke test HTTP, preflight de segurança, release check local e guia de deploy Hostinger.

Aplicado no Supabase remoto existente. Histórico de migrations remoto reparado para `0001` a `0013`.

Pendente para fechar E8: publicar na Hostinger, rodar smoke test na URL publicada e executar o teste SQL com usuários reais.

## F2 — Relatórios básicos (iniciada)

Implementado: menu "Relatórios", rota `/relatorios`, `ReportsSnapshot`, `ReportsRepository`, `ReportsNotifier` e tela gerencial neomórfica com indicadores de clientes ativos/inativos, chamados abertos, agendamentos pendentes, OS abertas/concluídas, média/contagem de satisfação, pipeline de orçamentos, saldo financeiro em aberto, vencido e recebido. A tela já possui filtro por período (`30 dias`, `Mês atual`, `Ano atual`, `Tudo`), busca nos rankings, filtro por situação (`Todos`, `Em aberto`, `Fechados`, `Financeiro`, `Agenda`), ação para copiar o resumo gerencial, exportação CSV coerente com os filtros ativos da tela, gráfico de tendência mensal com chamados/OS/recebimentos, ranking "Clientes em destaque", ranking "Tipos de serviço em alta" e ranking "Técnicos em campo". Os rankings abrem popups neomórficos de detalhe para cliente, tipo de serviço e técnico, sem trocar de página, com métricas no topo e movimentos recentes derivados de chamados, OS, recebíveis, agenda e apontamentos de horas.

Sem nova migration nesta etapa: a tela usa tabelas existentes e respeita o RLS atual do Supabase.

Correção aplicada: usuário autenticado com empresa ativa agora sai automaticamente de `/criar-empresa` para `/dashboard`, inclusive depois de criar a empresa ou ao acessar a URL manualmente.

Padrão visual aplicado: formulários de cadastro e popups de criação/ação usam `AppFormSection` e `AppFormGrid`, com campos lado a lado no desktop e quebra responsiva em telas menores.

Cadastro de cliente atualizado: no primeiro cadastro, o popup grava o cliente junto com pessoa de contato principal e endereco padrao. O contato principal nasce espelhando nome/telefone do cliente, mas pode ser alterado antes de salvar. O endereco inicia pelo CEP e tenta preencher rua, bairro, cidade e UF automaticamente.

Importacao de clientes atualizada: a lista de clientes agora possui acao `Importar clientes`, com popup para carga em lote via CSV. O fluxo valida nome, CPF/CNPJ, telefone, CEP e UF, reaproveita o mesmo cadastro de cliente/contato/endereco, bloqueia duplicidade por CPF/CNPJ e telefone e apresenta resumo do que foi importado, pulado ou ficou pendente para ajuste manual.

Composicao operacional atualizada: o cadastro de orçamento e o cadastro manual de OS agora aceitam múltiplas linhas de composição, incluindo serviço, hora técnica, material, deslocamento, extra e outros. Cada linha pode trazer `Profissional / especialidade` no descritivo para montar propostas e execuções com mais de um perfil no mesmo documento. As telas de detalhe de orçamento e OS também passaram a exibir essas linhas gravadas.

Agenda operacional atualizada: ao clicar em uma data da agenda mensal, o sistema agora abre uma agenda diária expandida com visão geral, lista lateral de profissionais, filtros por categoria operacional e grade de horários clicáveis. Cada horário livre pode abrir popup para agendar orçamento a partir de chamado ou agendar OS já existente, com busca de cliente por nome, CPF/CNPJ ou telefone.

Edicao de cliente atualizada: lista e detalhe exibem botao visivel `Editar cliente`, abrindo o mesmo formulario em popup e atualizando a lista/detalhe apos salvar.

Geolocalização de endereço atualizada: o cadastro de novo cliente e o cadastro/edição de endereços do cliente exibem bloco neomórfico `Localização para rotas`, com botão `Localizar`/`Atualizar` para buscar latitude/longitude via endereço preenchido. As coordenadas são salvas em `customer_addresses.latitude` e `customer_addresses.longitude`, sem nova migration.

Cadastro de chamado atualizado: o campo Cliente no popup de novo chamado virou busca/autocomplete dentro da propria lista, filtrando por nome, CPF, CNPJ ou telefone e exibindo documento/telefone nas sugestoes.

Pendente para evoluir F2: validação em staging com dados reais e refinamentos de drill-down conforme uso operacional.

## F2 — Pesquisa de satisfacao simples

Implementado e aplicado no Supabase remoto: migration `0014_customer_satisfaction.sql`, rollback, roteiro SQL manual, domínio `WorkOrderSatisfaction`, leitura no repositório de OS, provider de satisfação, painel no detalhe da OS, popup `Registrar satisfação` para OS concluida e indicadores de satisfação nos Relatórios, com média, contagem de avaliações e avaliações críticas. A RPC `record_work_order_satisfaction()` valida tenant, permissão `work_orders.execute`/`work_orders.manage`, exige OS concluída, registra evento operacional e auditoria `work_order.satisfaction.recorded`.

Pendente: executar `test/isolation/0013_customer_satisfaction_test.sql` com usuários reais.

## Atualização incremental — 2026-07-23

Implementado no app web:
- correção do overflow vertical da barra lateral no desktop, com `NavigationRail` rolável e menu do usuário desacoplado da lista de destinos;
- módulo `Pagamentos` convertido de placeholder para tela operacional com baixa manual, leitura de vencidos, pendentes e valores recebidos;
- módulo `Fiscal` convertido de placeholder para tela operacional com conferência de recibos, pendências documentais e visualização/impressão de comprovantes;
- módulo `Promoções` convertido de placeholder para tela inicial utilizável, usando a carteira de clientes já cadastrada para sugerir ativações comerciais por perfil.
- cadastro de profissionais ajustado para permitir salvar profissional interno sem vínculo imediato com usuário técnico, inclusive quando a lista de usuários internos vier vazia ou indisponível.
- agenda operacional ajustada para exibir todos os profissionais ativos cadastrados, inclusive parceiros e internos ainda sem vínculo, mantendo a exigência de usuário interno apenas no momento de confirmar o agendamento.

Status operacional:
- `Pagamentos`, `Fiscal` e `Promoções` já estão acessíveis pelo menu e pelo dashboard quando o plano libera a feature.
- `Campanhas`, `BI avançado` e `IA` continuam como próximas fases premium a operacionalizar.

## F2 — Fotos por etapa

Implementado e aplicado no Supabase remoto: componente reutilizável `PhotoAttachmentPicker`, fotos no cadastro/popup de novo chamado, novo orçamento e nova OS, upload privado para `service-request-attachments`, `quotation-attachments` e `work-order-evidence`, migration `0015_quotation_attachments.sql` e rollback. As fotos servem para identificação, catálogo e histórico de clientes, equipamentos, locais e serviços.

Complemento em andamento: orçamento e OS passaram a aceitar fotos e documentos no app, e foi adicionada a migration `0016_attachment_documents.sql` para liberar PDF e arquivos Office comuns em `quotation_attachments` e no bucket `work-order-evidence`.

## F2 — Rotas de campo

Implementado: dependência `url_launcher`, modelo `RouteDestination`, algoritmo `suggestFieldRoute`, painel `FieldRoutePanel`, botões `RouteActions` nos cards de Chamados, Orçamentos e OS, e enriquecimento dos repositórios para buscar endereço direto do atendimento ou endereço principal do cliente. O profissional pode abrir Google Maps, Waze, Apple Maps ou copiar o endereço. O roteiro sugerido ordena por criticidade/prioridade, horário/validade e distância aproximada quando latitude/longitude estiverem cadastradas.

Complemento implementado: `AddressGeocoder` e `AddressLocationBox` permitem preencher coordenadas diretamente no endereço do cliente, tornando o cálculo de distância do roteiro sugerido mais confiável.

## ADRs ativos

ADR-001..018 e ADR-021..023 registrados (ver DECISIONS.md). ADR-017 (decimal): usar `int` em centavos no MVP, reavaliar em E6. ADR-018 (testes RLS): SQL local via Supabase CLI. ADR-019 e ADR-020 pendentes para E6/F3.

# ServiceFlow — Relatório Técnico do Estado Atual

**Elaborado em:** 2026-07-24
**Escopo:** análise de código-fonte, migrations, testes e documentação do repositório `serviceflow`.
**Natureza:** somente leitura e diagnóstico. Nenhuma alteração de código foi feita.

---

## 1. Sumário executivo

O ServiceFlow é um SaaS multiempresa (multi-tenant) brasileiro de gestão de serviços técnicos em campo (Field Service Management), construído em **Flutter** (web-first, com Android/iOS preparados) sobre **Supabase** (PostgreSQL + Auth + RLS + Storage). A versão do pacote é `0.2.0+1`.

O projeto está substancialmente mais avançado do que um MVP típico: o fluxo comercial-operacional-financeiro completo (cliente → chamado → agenda → orçamento com link público → OS → execução → aceite → recebível → recibo) já está implementado em código, com 36 migrations versionadas, 143 arquivos Dart em `lib/` e uma suíte de testes Flutter razoável. Além do MVP, boa parte da **Fase 2** (planos/assinatura, onboarding por convite, checkout/webhooks, relatórios, satisfação, importação de clientes, rotas de campo, hubs de módulos premium) já foi construída.

O sistema **não está fechado como MVP** por dois tipos de pendência: (a) pendências operacionais externas — publicação em staging na Hostinger, execução dos testes de isolamento SQL com usuários reais e verificação ponta a ponta em ambiente real; e (b) três riscos técnicos internos que merecem atenção imediata, detalhados na seção 7 — destaque para o **enorme volume de trabalho não commitado** e uma **colisão de prefixo de migration (`0034`)**.

**Veredito:** o código do MVP está funcionalmente completo; o que falta para declará-lo "MVP entregue" é validação em ambiente real, testes de segurança executados e higiene de versionamento/migrations — não construção de novas funcionalidades.

---

## 2. Arquitetura atual

### 2.1 Estilo e stack

Monólito modular: um único app Flutter sobre Supabase, sem microserviços, com fronteiras lógicas por módulo. As regras críticas (cálculo financeiro, transições de estado, conversão orçamento→OS, numeração por tenant, aprovação por link público) residem no banco via funções SQL `SECURITY DEFINER` e RPCs, não no cliente Flutter.

| Camada | Tecnologia | Versão / observação |
|---|---|---|
| Frontend | Flutter / Dart | SDK `>=3.0.0 <4.0.0`, Material 3 |
| Estado | Riverpod (`flutter_riverpod`) | `^2.5.1`, providers por feature |
| Navegação | GoRouter (`go_router`) | `^14.0.0`, com guards de auth/plano |
| Modelos | Freezed + json_serializable | imutáveis onde agregam valor |
| Backend | Supabase (`supabase_flutter`) | `^2.8.0` — Postgres, Auth, RLS, Storage |
| PDF | `pdf` + `printing` | recibos e orçamentos com fonte embutida |
| Arquivos | `file_picker` | anexos/importação CSV |
| Externo | `url_launcher` | rotas de campo (Maps/Waze) |

### 2.2 Organização do código (feature-first)

O `lib/` segue arquitetura em camadas por feature: `presentation` → `application` → `domain` ← `data`. Regra observada no repositório: a apresentação não acessa tabelas diretamente, sempre via repository; dependências apontam para dentro.

```
lib/
  core/     config, theme, router/routing, error, utils, widgets, plans, files, location
  features/ auth, tenant, dashboard, customers, service_requests, scheduling,
            professionals, quotations, work_orders, financials, reports,
            settings, modules, promotions
  shared/   providers (supabase, auth, tenant) — Riverpod
  app/      domain/entities + infra/repositories (camada de abstração adicional)
```

Distribuição de arquivos Dart por feature (total 143 em `lib/`):

| Feature | Arquivos | Feature | Arquivos |
|---|---|---|---|
| customers | 21 | quotations | 10 |
| service_requests | 10 | scheduling | 9 |
| settings | 14 | work_orders | 8 |
| financials | 8 | reports | 8 |
| auth | 7 | professionals | 5 |
| tenant | 2 | dashboard | 1 |
| modules | 1 | promotions | 1 |

### 2.3 Backend Supabase

36 arquivos de migration versionados (`0001` a `0034`), cada um com rollback correspondente em `supabase/rollbacks/` (34 rollbacks). Segurança baseada em RLS "deny by default", funções `SECURITY DEFINER` mínimas (`current_tenant_id()`, `has_permission()`, etc.), buckets de Storage privados com paths por tenant e RPCs para operações sensíveis (criação de orçamento, conversão em OS, transições, pagamentos, aceite).

### 2.4 Rotas e ambientes

Rotas internas: `/clientes`, `/chamados`, `/agenda`, `/orcamentos`, `/ordens-servico`, `/financeiro`, `/relatorios`, mais rotas de detalhe (`:id`), edição de cliente, tela pública `/orcamento-publico/:token`, `/aceitar-convite`, `/onboarding-plano` e `/assinatura`. Guards redirecionam por estado de auth, ausência de tenant e bloqueio comercial (trial vencido / `past_due` / `canceled`).

Ambientes via `--dart-define-from-file`: existem `dart_defines/dev.example.json`, `staging.example.json` e um `dev.json` real (com credenciais, fora do controle de exemplo). Build web e empacotamento staging automatizados em `scripts/` (`build_staging.sh`, `release_check.sh`, `security_preflight.sh`, `smoke_web.sh`, `write_release_manifest.sh`).

---

## 3. Funcionalidades concluídas (implementadas no código)

### 3.1 Fundação (F0–F1)

- **Identidade, tenancy e RBAC** — `0001_foundation.sql`: 11 tabelas de identidade/tenancy, RLS, funções, seed de roles/permissions. Auth por e-mail/senha com `AuthNotifier`, login, recuperação e reset de senha.
- **Clientes, contatos, endereços, ativos** — CRUD completo, listagem paginada com busca/filtros e infinite scroll, detalhe em abas (Dados/Contatos/Endereços), formulários em popup, validações BR (CPF, CNPJ, CEP, telefone), auditoria e RLS. Inclui **importação em lote via CSV** com deduplicação e **geolocalização de endereço** (lat/long para roteirização).
- **Chamados** — categorias, prioridades, histórico de status, anexos (Storage + policies), notas, atribuições, filtros server-side, lista/detalhe/criação, autocomplete de cliente.
- **Agenda e visitas** — `appointments`, `appointment_assignments`, `technical_visits`, `visit_evidence`, RPC `schedule_appointment` com bloqueio transacional de conflito por técnico, calendário mensal + agenda diária por profissional com grade de horários clicáveis.
- **Orçamentos** — versões, itens multi-linha (serviço, hora técnica, material, deslocamento, extra), cálculo server-side em centavos, geração de PDF, **link público seguro** (token hasheado) com tela pública de aprovação/rejeição e revogação manual.
- **Ordens de Serviço e execução** — conversão idempotente de orçamento aprovado, transições de status, apontamento de horas, materiais aplicados, despesas operacionais, evidências em bucket privado e **aceite do cliente com assinatura desenhada**.
- **Financeiro mínimo** — recebíveis, registro manual de pagamento, recibos numerados com PDF, tela financeira com resumo, botão "Gerar cobrança" na OS e dashboard com indicadores financeiros.
- **Infra de release** — pacote `.zip` de staging, manifesto SHA-256, smoke test HTTP, preflight de segurança e release check local (reportados como "passou" em 2026-07-22).

### 3.2 Fase 2 (parcial, já iniciada além do MVP)

- **Planos e assinatura** — catálogo `Starter/Professional/Business/Enterprise` (modelo `TenantPlanDefinition` + enum `TenantFeature` com 19 features), limites de usuários/unidades, `plan_key`/`billing_status`/`trial_ends_at`, imposição de limite e bloqueio de downgrade.
- **Onboarding por convite** — tela pública `/aceitar-convite`, criação de conta a partir do token, onboarding obrigatório de plano após criar empresa, bloqueio comercial suave.
- **Checkout e billing** — sessões de checkout rastreáveis, confirmação/ativação, encerramento (cancelada/expirada) e **registro de webhooks de cobrança** (migrations `0031`–`0034`) — porém **ainda sem gateway real integrado** (status muda manualmente ou via simulação).
- **Profissionais formais** — cadastro dedicado de profissionais/parceiros com categoria, status e vínculo opcional a usuário interno; agenda passou a usar esse cadastro como fonte oficial; custos e disponibilidade (`0019`, `0020`).
- **Relatórios gerenciais** — snapshot com indicadores (clientes, chamados, agenda, OS, satisfação, pipeline de orçamentos, saldo financeiro), filtros por período/situação, busca, exportação CSV, gráfico de tendência mensal e rankings com drill-down em popup.
- **Satisfação** — pesquisa simples na OS concluída com RPC auditada e indicadores nos relatórios.
- **Rotas de campo** — algoritmo `suggestFieldRoute`, painel e botões para Google Maps/Waze/Apple Maps a partir dos cards de Chamados/Orçamentos/OS.
- **Fotos e documentos por etapa** — `PhotoAttachmentPicker` reutilizável, upload privado por bucket, suporte a PDF/Office.
- **Hubs de módulos premium** — telas-base/operacionais iniciais para Pagamentos, Fiscal, Promoções, Campanhas, BI avançado e IA, condicionadas ao plano (Pagamentos e Fiscal já operacionais reaproveitando o financeiro; Promoções utilizável; Campanhas/BI/IA ainda placeholders).

### 3.3 Testes existentes

Suíte Flutter cobrindo auth/validators, notifiers de clientes/orçamentos/chamados/agenda, telas de dashboard/financeiro/relatórios/OS/orçamento, PDF de recibo e orçamento, redirecionamentos do router, importação de clientes, planos e checkout. Existem **13 roteiros SQL de isolamento** em `test/isolation/` (RLS por tabela), ainda **não executados** contra usuários/UUIDs reais.

---

## 4. O que falta para o MVP

O MVP só é declarado "operacional" quando o fluxo cadastro→pagamento é testado ponta a ponta **em staging**. As pendências não são de construção de features, e sim de validação, segurança e publicação:

### 4.1 Pendências externas / operacionais (bloqueiam o aceite do MVP)

1. **Publicar na Hostinger** — o pacote de staging e o smoke test local estão prontos; falta a publicação e o smoke test contra a URL real. (Depende de acesso externo à hospedagem.)
2. **Executar os testes de isolamento SQL com usuários reais** — os 13 roteiros de `test/isolation/` exigem criar usuários no Supabase Auth, substituir UUIDs no seed e rodar. **Isolamento entre tenants "testado" é critério explícito de aceite do MVP** e ainda não foi cumprido.
3. **Seed real** — criar usuários de teste (incluindo técnico ativo) e atualizar `supabase/seed/dev_seed.sql`.
4. **Verificação manual ponta a ponta** — executar o fluxo completo (criar cliente/chamado/orçamento → aprovar → converter em OS → executar → horas/material/despesa/evidência → aceite com assinatura → gerar cobrança → registrar pagamento) e conferir `audit_logs`.
5. **Backup configurado** — item do checklist de aceite ainda a confirmar.

### 4.2 Pendências de construção que ainda tocam o MVP/F2 imediata

6. **Gateway de pagamento real** — o checkout/assinatura hoje muda status manualmente ou por simulação de webhook; a integração real de cobrança é a "entrega em andamento" declarada, mas não é bloqueante do MVP operacional (billing é F2+ por decisão de produto).
7. **Reutilização do cadastro de profissionais** — falta conectar o cadastro formal às linhas de orçamento/OS, ao planejamento de roteiro e ao apontamento por parceiro.
8. **Evolução dos hubs premium** — Campanhas, BI avançado e IA seguem como placeholders; Pagamentos/Fiscal precisam virar módulos operacionais completos.

### 4.3 Critérios de aceite do MVP — situação

| Critério (ROADMAP §3) | Situação |
|---|---|
| Publicado em staging | ⏳ pendente (Hostinger) |
| Acessível desktop + mobile | ✅ web responsivo (shell com NavigationRail) |
| Autenticação | ✅ e-mail/senha |
| Isolamento entre tenants **testado** | ⏳ scripts prontos, execução pendente |
| Fluxo completo cliente→...→documento sem duplicidade | ✅ em código / ⏳ validação real |
| Auditoria ativa | ✅ `audit_logs` + eventos |
| Backup configurado | ⏳ a confirmar |
| Nenhuma chave admin no Flutter | ✅ preflight cobre; ⏳ confirmar em staging |
| `flutter analyze` + testes verdes | ✅ reportado como "passou" localmente |
| Sem vulnerabilidade crítica conhecida | ⏳ depende dos testes de isolamento reais |
| Docs de implantação e rollback | ✅ presentes |

---

## 5. Documentação encontrada

A documentação é um ponto forte do projeto — completa, versionada e organizada em `docs/`:

`DOCS_INDEX.md` (índice), `VISION.md`, `ARCHITECTURE.md`, `DATA_MODEL.md`, `DECISIONS.md` (ADRs), `SECURITY.md`, `THREAT_MODEL.md` (STRIDE), `ROADMAP.md`, `DELIVERY_1.md` (fundação consolidada), `PROJECT_STATE.md` (estado detalhado), `CHANGELOG.md` (558 linhas), `SYSTEM_MANUAL.md`, `SQL_MANUAL.md`, `RECREATE_PROMPT.md` (prompt mestre de reconstrução), `DEPLOY_STAGING.md`, `MVP_RELEASE_CHECK.md`, `RELEASE_NOTES_MVP.md` e `docs/imports/` (preview de CSV de clientes).

**Observação:** o `PROJECT_STATE.md` está levemente defasado em um ponto — descreve migrations "0001 a 0018" no cabeçalho da estrutura, enquanto o repositório já contém até `0034`. O corpo do documento e o CHANGELOG, porém, mencionam `0029`–`0034`, então trata-se de defasagem pontual do cabeçalho, não do conteúdo.

---

## 6. Métricas do repositório

| Métrica | Valor |
|---|---|
| Arquivos Dart em `lib/` | 143 |
| Features em `lib/features/` | 14 |
| Migrations SQL | 36 (`0001`–`0034`) |
| Rollbacks SQL | 34 |
| Roteiros de isolamento SQL | 13 |
| Arquivos de teste Dart | 30 |
| Documentos em `docs/` | 18 + imports |
| Versão do pacote | `0.2.0+1` |
| Commits no histórico Git | 2 |

---

## 7. Riscos técnicos e achados (atenção imediata)

1. **Trabalho não versionado (CRÍTICO).** O histórico Git tem apenas **2 commits** (E2 e E3), mas há **156 mudanças pendentes** (54 arquivos modificados, 100 não rastreados). Praticamente todo o trabalho de E4–E8 e da Fase 2 — orçamentos, OS, financeiro, planos, checkout, relatórios — está **fora do controle de versão**. Um incidente no diretório de trabalho hoje perderia semanas de desenvolvimento. Além disso, existe um `.git/index.lock` presente que está **bloqueando novos commits** (o `PROJECT_STATE.md` já registra a necessidade de `rm .git/index.lock`).

2. **Colisão de prefixo de migration `0034` (ALTO).** Há dois arquivos com o mesmo prefixo: `0034_list_all_active_professionals_in_schedule.sql` e `0034_tenant_billing_webhook_events.sql`. Isso gera ambiguidade de ordem de execução e pode quebrar `supabase db push` ou o alinhamento do histórico remoto. Recomenda-se renumerar um deles (ex.: `0035_...`) antes de qualquer novo push.

3. **Artefatos gerados / build_runner (MÉDIO).** Existem apenas 4 arquivos `*.freezed.dart` e 4 `*.g.dart` em `lib/`, embora vários modelos de domínio usem Freezed. A documentação confirma que `flutter pub run build_runner build` é obrigatório antes de compilar. Qualquer novo ambiente precisa rodar o build_runner; convém garantir isso no fluxo de release e no CI para evitar falhas de compilação silenciosas.

4. **Defasagem pontual de documentação (BAIXO).** Cabeçalho do `PROJECT_STATE.md` cita migrations até `0018`; o real é `0034`. Atualizar para manter a regra do próprio projeto (docs sincronizadas a cada nova migration/fase).

5. **Credenciais em `dart_defines/dev.json` (verificar).** O arquivo real existe no diretório. Confirmar que está no `.gitignore` (o preflight de segurança cobre isso, mas vale verificação explícita antes de qualquer commit em massa, dado o item 1).

---

## 8. Recomendações de sequência (sem implementar agora)

Ordem sugerida quando você autorizar a execução:

1. Resolver o versionamento: remover `.git/index.lock`, confirmar `.gitignore` (env/segredos), e commitar o trabalho E4–F2 em incrementos coerentes.
2. Renumerar a migration `0034` duplicada e revalidar a sequência de migrations + rollbacks.
3. Rodar `build_runner`, `flutter analyze` e a suíte de testes num ambiente limpo.
4. Criar o seed real e **executar os 13 testes de isolamento SQL** — este é o item de segurança que trava o aceite do MVP.
5. Publicar em staging (Hostinger) e rodar o smoke test contra a URL real.
6. Fazer a verificação manual ponta a ponta e conferir auditoria.
7. Atualizar `PROJECT_STATE.md`/`CHANGELOG.md` e fechar o checklist do MVP.

---

*Fim do relatório. Nenhuma alteração de código foi realizada — aguardando instruções.*

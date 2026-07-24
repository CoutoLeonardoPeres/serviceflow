# ServiceFlow — Roadmap, Backlog e Critérios

Estimativas relativas: P (≤1 sessão), M (1–2), G (2–4), GG (4+).

## 1. Plano das oito primeiras entregas (Fases 0–1)

| # | Entrega | Conteúdo | Tamanho | Depende de |
|---|---|---|---|---|
| 1 | Visão e arquitetura | Docs desta pasta | M | — |
| 2 | Fundação técnica | Flutter init, pastas, tema, env, Supabase, migrations identidade+tenancy, RLS, auth (login/recuperação/convite), shell responsivo, testes de isolamento | GG | 1 |
| 3 | Clientes | customers/contacts/addresses, validações BR (CPF/CNPJ/CEP/fone), RBAC aplicado, auditoria, testes | G | 2 |
| 4 | Chamados | service_requests, categorias, prioridades, histórico de status, anexos (Storage+policies), atribuição, filtros server-side, testes | G | 3 — concluída |
| 5 | Agenda e visitas | appointments, técnicos, conflito de agenda, technical_visits, testes | M | 4 — concluída |
| 6 | Orçamentos | quotations, versões, itens, cálculo server-side, PDF, link público seguro, aprovação pública e revogação manual implementados; execução do teste SQL específico com usuários reais pendente | GG | 3 (4/5 desejáveis) — base concluída |
| 7 | OS e execução | work_orders, itens espelhados, eventos, evidências, lista, criação em popup, detalhe, transição de execução, conversão idempotente de orçamento aprovado, registro de horas, materiais, despesas, anexos reais no Storage e aceite com assinatura desenhada implementados; testes SQL com usuários reais pendentes | GG | 6 — base concluída |
| 8 | Financeiro mínimo + deploy | receivables, payment_records, baixa manual, recibos numerados, PDF do recibo, dashboard mínimo, tela financeira, pacote staging e smoke test local implementados; publicação Hostinger e smoke test remoto pendentes | G | 7 — em andamento |

MVP declarado operacional somente com o fluxo completo (cadastro→pagamento) testado ponta a ponta em staging.

## 2. Backlog priorizado (épicos além da E8)

| Prioridade | Épico | Fase | Tamanho |
|---|---|---|---|
| 1 | Estabilização: numeração por tenant refinada, versionamento de orçamento completo, cancelamentos controlados, retornos, histórico ampliado | F2 | G |
| 2 | Permissões refinadas + auditoria ampliada + monitoramento + backup/restore validado | F2 | G |
| 3 | Templates de mensagem + outbox + registro de comunicação | F2 | M |
| 4 | Importação de clientes (CSV), relatórios básicos, testes E2E | F2 | M |
| 5 | Pesquisa de satisfação simples | F2 | P — base local implementada; aplicar migration remota e validar com usuários reais |
| 6 | Estoque completo + compras + fornecedores | F3 | GG |
| 7 | Financeiro completo (pagar, fluxo de caixa, conciliação, DRE) | F4 | GG |
| 8 | Parceiros e repasses | F5 | G |
| 9 | Contratos, SLA e preventivas | F6 | GG |
| 10 | Frota | F7 | G |
| 11 | Integrações (WhatsApp oficial, e-mail transacional, gateway/Pix, mapas, fiscal, webhooks) | F8 | GG |
| 12 | BI e automações | F9 | GG |
| 13 | Assinaturas/planos do SaaS + admin da plataforma completo | F2+ | G — base de planos/trial iniciada em 2026-07-23 |

## 3. Critérios de aceite do MVP

Conforme §22 da especificação — resumo verificável: publicado em staging; acessível desktop+mobile; autenticação; isolamento entre tenants **testado**; fluxo completo cliente→chamado→agenda→orçamento→link→aprovação (sem duplicidade)→OS→execução→evidências→conclusão→recebimento→documento; auditoria ativa; backup configurado; nenhuma chave administrativa no Flutter; `flutter analyze` e testes verdes; sem vulnerabilidade crítica conhecida; docs de implantação e rollback.

## 4. Definition of Done (por entrega)

1. Código compila; `dart format` e `flutter analyze` limpos.
2. Migrations aplicadas e reversíveis/expand-and-contract; validadas em banco limpo.
3. RLS + testes de isolamento para toda tabela nova.
4. Testes unitários das regras de domínio; testes dos fluxos críticos tocados.
5. Testes de segurança pertinentes à entrega passando (com resultado real reportado).
6. Auditoria para as ações sensíveis introduzidas.
7. Sem segredos no código; scan limpo.
8. PROJECT_STATE.md e CHANGELOG.md atualizados; ADRs novos registrados.
9. Passos de validação manual documentados.
10. Nenhum TODO crítico sem registro.

## 5. Fases seguintes (F2–F9)

Conteúdo conforme especificação §20 — não detalhar nem implementar antes da fase correspondente.

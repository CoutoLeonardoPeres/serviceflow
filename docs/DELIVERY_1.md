# ServiceFlow - Entrega 1: Visao, Arquitetura e Escopo

**Data:** 2026-07-21  
**Status:** concluida como documentacao de fundacao; este arquivo consolida os artefatos ja distribuidos em `VISION.md`, `ARCHITECTURE.md`, `DATA_MODEL.md`, `SECURITY.md`, `THREAT_MODEL.md`, `ROADMAP.md` e `DECISIONS.md`.

## 1. Objetivo da entrega

Definir a base de produto, dominio, seguranca e arquitetura antes de novas implementacoes. A entrega nao cria codigo, migrations ou telas; ela fixa o que sera construido nas entregas seguintes e quais riscos precisam ser controlados desde o inicio.

## 2. Escopo incluido

- Visao do produto e proposta de valor.
- Personas principais.
- Jornada ponta a ponta do atendimento.
- Escopo funcional completo e escopo do MVP.
- Itens explicitamente fora do MVP.
- Modulos previstos e sua ordem incremental.
- Arquitetura proposta e diagrama textual de componentes.
- Modelo de ameacas STRIDE.
- Modelo inicial de dados.
- Matriz simplificada de papeis e permissoes.
- Maquinas de estado iniciais.
- Backlog priorizado e plano das oito primeiras entregas.
- Criterios de aceite, Definition of Done, riscos e ADRs.

## 3. Escopo excluido

- Projeto Flutter novo ou reestruturacao completa.
- Migrations novas.
- Telas, autenticacao, clientes, chamados, agenda, orcamentos ou OS.
- Integracoes reais com WhatsApp, pagamento, mapas, fiscal ou e-mail.
- Estoque, compras, parceiros, contratos, frota, BI avancado e automacoes.
- Deploy em Hostinger ou configuracao de staging.

## 4. Visao do produto

ServiceFlow e um SaaS B2B multiempresa para gestao de field service no Brasil. O produto controla o ciclo completo de atendimento tecnico: contato inicial, cadastro do cliente, chamado, visita, orcamento, aprovacao, ordem de servico, execucao em campo, aceite, recebimento e indicadores.

Proposta de valor central: uma pequena empresa consegue operar atendimentos reais sem depender de planilhas, mensagens soltas e controles manuais, preservando rastreabilidade, seguranca e separacao entre empresas desde a primeira versao.

Direcao de mercado para o MVP: manter requisitos genericos de field service, sem especializar o fluxo inicial para eletrica, hidraulica, refrigeracao ou outra vertical. Sugestao aceita: preparar categorias, catalogo e campos livres configuraveis para acomodar especialidades por tenant sem criar regras verticais prematuras.

## 5. Personas

| Persona | Papel inicial | Necessidade principal |
|---|---|---|
| Dono ou gestor | `tenant_owner`, `manager` | Controlar atendimento, margem, faturamento e qualidade. |
| Analista ou atendente | `analyst` | Registrar clientes, chamados e informacoes completas rapidamente. |
| Despachante | `dispatcher` | Organizar agenda, tecnicos e visitas. |
| Tecnico de campo | `technician` | Executar OS no celular, registrar horas, fotos, materiais e aceite. |
| Financeiro | `financial_operator` | Registrar recebimentos, recibos e baixas com controle. |
| Cliente final | link publico ou `customer_portal_user` | Aprovar orcamento, acompanhar atendimento e assinar aceite sem criar conta. |
| Administrador da plataforma | `platform_admin` | Operar o SaaS sem acesso livre a dados dos tenants. |
| Parceiro terceirizado | `partner` futuro | Receber OS atribuidas e controlar repasses. |

## 6. Mapa da jornada

```text
Contato recebido
  -> localizar ou cadastrar cliente
  -> registrar chamado com problema, prioridade, endereco e anexos
  -> triagem
  -> agendar visita tecnica quando necessario
  -> registrar diagnostico
  -> gerar orcamento com servicos, horas, materiais, despesas, impostos e desconto
  -> enviar PDF ou link seguro
  -> cliente aprova, rejeita ou solicita alteracao
  -> registrar adiantamento quando exigido
  -> converter orcamento aprovado em OS de forma idempotente
  -> agendar e designar tecnico ou parceiro
  -> executar servico com check-in, horas, evidencias, materiais e despesas
  -> concluir e colher aceite
  -> emitir recibo ou solicitar documento fiscal
  -> registrar pagamento e baixa
  -> atualizar indicadores
```

## 7. Escopo funcional do produto-alvo

O produto-alvo inclui os modulos de identidade, tenant, assinaturas, usuarios, equipes, clientes, contatos, enderecos, chamados, agenda, visitas tecnicas, orcamentos, ordens de servico, horas, materiais, estoque, compras, fornecedores, financeiro, pagamentos, fiscal, parceiros, comissoes, contratos, preventivas, frota, despesas, comunicacao, satisfacao, relatorios, indicadores, auditoria e administracao SaaS.

## 8. Escopo do MVP

O MVP operacional minimo compreende:

- Autenticacao, recuperacao de senha, tenant, membership, RBAC, RLS e auditoria basica.
- Cadastro de clientes, contatos e enderecos.
- Tecnicos, catalogo basico de servicos e materiais.
- Abertura, listagem, filtro e detalhe de chamados.
- Agenda basica e visita tecnica.
- Orcamento com itens, calculos, versionamento, PDF e link seguro.
- Aprovacao por link sem conta, com protecoes contra duplicidade.
- Conversao para OS, execucao em campo, evidencias, materiais, despesas e aceite.
- Recebimento manual, contas a receber basicas, recibo simples.
- Dashboard operacional minimo.
- Publicacao em staging com testes e smoke test.

## 9. Fora do MVP

Ficam fora do MVP: estoque completo, compras, fornecedores, financeiro completo, gateway de pagamento, Pix automatico, emissao fiscal propria, API oficial de WhatsApp, mapas integrados, parceiros e repasses, contratos, preventivas, frota, BI avancado, automacoes, modo offline completo e multi-tenancy avancado na UI para usuarios em varias empresas.

## 10. Modulos

| Grupo | Modulos | Fase |
|---|---|---|
| Fundacao | Identidade, acesso, tenant, membership, RBAC, auditoria | F0 |
| Operacao minima | Clientes, contatos, enderecos, chamados, agenda, visitas | F1 |
| Comercial | Orcamentos, itens, aprovacoes, documentos | F1 |
| Execucao | OS, apontamento, evidencias, materiais simples, despesas, aceite | F1 |
| Financeiro minimo | Recebiveis, pagamentos manuais, recibo | F1 |
| Estabilizacao | Historico, permissoes refinadas, anexos, auditoria ampliada | F2 |
| Backoffice | Estoque, compras, financeiro completo, parceiros, contratos, frota | F3-F7 |
| Integracoes e dados | WhatsApp, e-mail, gateway, fiscal, mapas, BI, automacoes | F8-F9 |

## 11. Arquitetura proposta

Estilo: monolito modular, sem microservicos prematuros.

Frontend: Flutter com Material 3, Riverpod, GoRouter, arquitetura feature-first, responsividade para web e mobile, internacionalizacao preparada com pt-BR inicial.

Backend: Supabase com PostgreSQL, Auth, RLS, Storage e Edge Functions para operacoes privilegiadas. Regras criticas ficam no banco ou em Edge Functions, nao apenas no Flutter.

Autenticacao do MVP: Supabase Auth com e-mail e senha, recuperacao de senha e confirmacao de e-mail configuravel. SSO, OAuth social, login com Google/Facebook e SAML ficam fora do MVP, mas a arquitetura nao deve impedir inclusao futura.

Hospedagem: Flutter Web como site estatico na Hostinger; VPS Hostinger somente se houver necessidade objetiva futura de worker persistente, fila externa ou servico incompatível com Edge Functions.

Ambientes: `development`, `staging` e `production`, com projetos Supabase separados e variaveis por ambiente. Nenhum segredo administrativo no Flutter.

Staging: a publicacao em staging entra como criterio de aceite do MVP e da Entrega 8. Para as entregas anteriores, deve-se manter configuracao preparada e documentada, mas credenciais, dominio e conta Hostinger/Supabase reais dependem de provisao operacional do projeto.

Capacidade de execucao: estimativas P/M/G/GG sao relativas a complexidade, risco e superficie tecnica, nao a calendario. Premissa atual: uma pessoa/agente senior multidisciplinar conduzindo entregas incrementais; se houver equipe maior, as estimativas podem ser paralelizadas por modulo, mas RLS, migrations e regras criticas continuam com revisao centralizada.

## 11.1 Direcao visual e UX

Direcao aprovada: visual moderno e futurista com neomorfismo inspirado no print de referencia, adaptado para um SaaS operacional B2B.

Princípios de UI:

- Fundo claro frio, paineis com sombra suave e relevo discreto.
- Acento principal violeta/azul para chamadas de acao, estados ativos e foco de navegacao.
- Cantos arredondados, porem com densidade suficiente para tabelas, listas e formularios operacionais.
- Microinteracoes e animacoes curtas para transicoes, hover, selecao, carregamento e feedback de sucesso.
- Contraste, foco de teclado e estados de erro sempre priorizados sobre estetica neomorfica.
- Evitar excesso de cartoes decorativos em telas de trabalho; usar o estilo em botoes, barras, filtros, cards repetidos e paineis de resumo.
- Mobile-first para tecnico em campo; desktop eficiente para analista, gestor e financeiro.

Token visual inicial sugerido:

| Papel | Valor |
|---|---|
| Fundo | `#E9EEF4` |
| Superficie elevada | `#F3F6FA` |
| Texto principal | `#2F3A46` |
| Texto secundario | `#687281` |
| Acento principal | `#6C5CF6` |
| Acento secundario | `#27C7B8` |
| Erro | `#D64550` |
| Sombra escura suave | `rgba(123, 137, 154, 0.28)` |
| Luz superior | `rgba(255, 255, 255, 0.88)` |

Assinatura visual: "painel de comando em relevo", combinando shell responsivo com cards operacionais suaves, botoes elevados, indicadores discretos e uma peca hero apenas em telas institucionais ou login. Nas telas internas, o design deve parecer uma ferramenta de operacao, nao uma landing page.

## 12. Diagrama textual de componentes

```text
[Flutter Web / Android / iOS]
  -> [Supabase Auth]
       login, recuperacao de senha, sessoes, convites
  -> [PostgREST + PostgreSQL]
       CRUD sob RLS, funcoes SQL, triggers, auditoria, historico
  -> [Supabase Storage]
       anexos por tenant, policies, URLs assinadas
  -> [Edge Functions]
       links publicos, aprovacoes, PDFs, conversoes, webhooks futuros

[Cliente final]
  -> [Pagina publica Flutter Web]
  -> [Edge Function com token hasheado, escopo minimo e rate limit]

[Hostinger]
  -> hospeda build web estatico sem segredos
```

## 13. Modelo de ameacas STRIDE

| Categoria | Ameaca principal | Controle inicial |
|---|---|---|
| Spoofing | Uso indevido de sessao, link publico ou convite | Supabase Auth, tokens fortes, hash de token, expiracao, revogacao, rate limit. |
| Tampering | Alteracao de `tenant_id`, valores financeiros ou status | RLS, tenant derivado do usuario, calculo server-side, funcoes transacionais e auditoria. |
| Repudiation | Usuario ou cliente nega aprovacao/alteracao | `audit_logs`, historico de status, versao aprovada, IP proporcional, user-agent e timestamp. |
| Information Disclosure | Vazamento horizontal entre tenants ou vertical por papel | Deny by default, policies por membership/permissao, testes de isolamento e escopo por link. |
| Denial of Service | Flood em login, links publicos, upload ou consultas pesadas | Rate limit, limites de upload, paginacao server-side, indices e mensagens controladas. |
| Elevation of Privilege | Autopromocao ou abuso de funcao privilegiada | RBAC no banco, `SECURITY DEFINER` minimo, `search_path` fixo, break-glass auditado. |

Estrategia recomendada para isolamento alem de RLS:

- Projetos Supabase separados por ambiente.
- RLS deny-by-default em todas as tabelas expostas.
- `tenant_id` definido pelo servidor, nunca confiado do cliente.
- Funcoes privilegiadas minimas, com `search_path` fixo e revisao obrigatoria.
- Testes automatizados de leitura e escrita entre tenants a cada migration.
- Storage segregado por path de tenant e policies espelhando membership.
- Auditoria de acoes sensiveis e fluxo break-glass para suporte.
- Backups, restore testado e segregacao de credenciais por ambiente.

## 14. Modelo inicial de dados

Entidades de fundacao:

- `tenants`, `tenant_settings`, `tenant_sequences`.
- `profiles`, `tenant_memberships`, `roles`, `permissions`, `role_permissions`.
- `user_invitations`, `audit_logs`.

Entidades do MVP:

- Clientes: `customers`, `customer_contacts`, `customer_addresses`, `customer_assets`, `customer_portal_access`.
- Chamados: `service_requests`, `service_categories`, `service_priorities`, `service_request_status_history`, `service_request_attachments`, `service_request_notes`, `service_request_assignments`.
- Agenda e visitas: `appointments`, `appointment_assignments`, `technical_visits`, `visit_evidence`.
- Orcamentos: `quotations`, `quotation_versions`, `quotation_items`, `quotation_public_links`, `quotation_approvals`, `quotation_status_history`.
- OS: `work_orders`, `work_order_items`, `work_order_assignments`, `work_order_time_entries`, `work_order_materials`, `work_order_expenses`, `work_order_evidence`, `work_order_signatures`, `work_order_status_history`.
- Catalogo: `service_catalog`, `labor_rate_tables`, `products`, `units_of_measure`, `tax_profiles`.
- Financeiro minimo: `receivables`, `payment_records`, `receipts`, `generated_documents`.

Regras globais:

- UUID como identificador externo.
- `tenant_id` em toda tabela pertencente a empresa.
- `created_at`, `updated_at`, `created_by`, `updated_by` quando aplicavel.
- RLS em todas as tabelas expostas.
- Valores monetarios no banco em `numeric`, nunca `float`.
- Unicidade sempre considerando `tenant_id`.
- Status controlado por maquina de estados, nao por atualizacao livre.

Nivel de detalhamento adotado: modelar em profundidade apenas as entidades necessarias para MVP e fundacao. Entidades futuras sao esbocadas para evitar becos sem saida arquiteturais, mas nao devem virar migrations ate a fase correspondente.

## 15. Matriz simplificada de papeis e permissoes

| Papel | Permissoes iniciais |
|---|---|
| `platform_admin` | Administra a plataforma, sem acesso default a dados de tenant; suporte apenas por fluxo auditado. |
| `tenant_owner` | Controle completo do tenant, usuarios, configuracoes e operacao. |
| `tenant_admin` | Administracao operacional do tenant, exceto acoes reservadas ao owner. |
| `manager` | Operacao, orcamentos, OS, agenda, relatorios e limites de desconto definidos. |
| `analyst` | Clientes, chamados, contatos, enderecos e orcamentos basicos. |
| `dispatcher` | Agenda, atribuicoes, chamados e acompanhamento operacional. |
| `technician` | Visualiza e atualiza apenas atendimentos atribuidos; sem financeiro amplo. |
| `financial_operator` | Recebiveis, pagamentos manuais, recibos e visao financeira autorizada. |
| `warehouse_operator` | Futuro estoque, movimentacoes e inventario. |
| `partner` | Futuras OS atribuidas ao parceiro e repasses permitidos. |
| `customer_portal_user` | Acesso restrito aos proprios registros ou por link seguro. |
| `viewer` | Leitura limitada conforme modulo permitido. |

Nao adicionar perfis novos no MVP alem dos papeis acima. Sugestao aceita: manter `warehouse_operator` e `partner` como papeis reservados para fases futuras, sem liberar funcionalidades ate estoque/parceiros existirem.

## 16. Maquinas de estado

Chamado:

```text
draft -> opened -> triage -> awaiting_customer -> triage
triage -> scheduled -> converted_to_quote | converted_to_work_order | closed
qualquer estado nao-terminal -> cancelled
```

Orcamento:

```text
draft -> under_review -> sent -> viewed -> awaiting_approval
awaiting_approval -> approved | rejected | change_requested
change_requested -> draft
approved -> partially_paid -> converted_to_work_order
sent/viewed/awaiting_approval -> expired | cancelled
```

Ordem de Servico:

```text
draft -> awaiting_schedule -> scheduled -> dispatched -> technician_en_route
technician_en_route -> on_site -> in_progress
in_progress -> paused | awaiting_material | awaiting_customer | completed
paused/awaiting_material/awaiting_customer -> in_progress
completed -> customer_accepted -> invoiced -> financially_closed
completed/customer_accepted -> return_required
qualquer estado nao-terminal -> cancelled
```

Pagamento:

```text
pending -> processing -> authorized -> paid
pending/processing -> failed | cancelled
paid -> refunded | partially_refunded | disputed
receivable agregado -> partially_paid quando saldo parcial
```

## 17. Backlog priorizado

| Prioridade | Entrega ou epico | Tamanho |
|---|---|---|
| 1 | E2 - Fundacao tecnica, auth, tenancy, RBAC, RLS | GG |
| 2 | E3 - Clientes, contatos, enderecos, validacoes e auditoria | G |
| 3 | E4 - Chamados, categorias, prioridades, historico, anexos e filtros | G |
| 4 | E5 - Agenda, tecnicos, conflitos e visitas | M |
| 5 | E6 - Orcamentos, calculos, PDF e link publico seguro | GG |
| 6 | E7 - Conversao para OS e execucao em campo | GG |
| 7 | E8 - Recebimento manual, recibo, dashboard minimo e staging | G |
| 8 | F2 - Estabilizacao, auditoria ampliada, relatorios e E2E | G |
| 9 | F3-F4 - Estoque, compras e financeiro completo | GG |
| 10 | F5-F9 - Parceiros, contratos, frota, integracoes, BI e automacoes | GG |

## 18. Criterios de aceite da Entrega 1

- Documentos de visao, arquitetura, dados, seguranca, ameacas, decisoes, roadmap e estado existem em `docs/`.
- MVP e fora do MVP estao explicitamente separados.
- Multitenancy, RLS e RBAC estao definidos como requisitos da fundacao.
- STRIDE registra ameacas e mitigacoes iniciais.
- Modelo de dados inicial lista entidades do MVP sem detalhar modulos futuros alem do necessario.
- O plano incremental das oito entregas esta definido.
- ADRs iniciais foram registradas.
- Perguntas bloqueadoras foram avaliadas.

## 19. Definition of Done

Uma entrega so pode ser considerada concluida quando:

- O sistema compila, quando houver codigo.
- `dart format --set-exit-if-changed`, `flutter analyze` e testes relevantes forem executados com resultado real.
- Migrations forem aplicadas e verificadas em banco limpo, quando existirem.
- RLS e isolamento entre tenants forem testados para cada tabela nova.
- Regras criticas tiverem testes de unidade, banco ou integracao.
- Segredos nao estiverem no Git nem no bundle Flutter.
- Auditoria existir para acoes sensiveis introduzidas.
- `PROJECT_STATE.md`, `CHANGELOG.md` e ADRs forem atualizados.
- Houver passos objetivos de validacao manual.
- Pendencias e riscos reais forem registrados.

## 20. Riscos tecnicos

| Risco | Severidade | Mitigacao |
|---|---|---|
| Vazamento horizontal entre tenants | Critica | RLS deny-by-default, testes SQL por entrega, revisao de funcoes privilegiadas. |
| `tenant_id` aceito do cliente | Critica | Derivar tenant no servidor por membership ativa. |
| Link publico conceder acesso amplo | Alta | Token hasheado, escopo minimo, expiracao, revogacao e auditoria. |
| Calculo financeiro divergente | Alta | Fonte da verdade no servidor; Flutter apenas pre-visualiza. |
| Aprovacao duplicada criar duas OS | Alta | Idempotencia, unique constraints e transacoes. |
| PDF ou anexos exporem dados | Media | Storage por tenant, URL assinada, checksum e policies. |
| Complexidade do MVP crescer demais | Alta | Entregas pequenas e faseamento estrito. |

## 21. Riscos de negocio

| Risco | Severidade | Mitigacao |
|---|---|---|
| MVP demorar por excesso de modulos | Alta | Nao implementar fases avancadas antes do fluxo minimo. |
| Usuarios preferirem WhatsApp informal | Media | Fluxo simples, link sem conta e registro manual de comunicacao. |
| Fiscal brasileiro travar operacao | Alta | Sem motor fiscal no MVP; recibo simples e abstracao futura. |
| Concorrentes mais maduros | Media | Foco em micro e pequenas empresas, rapidez operacional e simplicidade. |
| Baixa adesao por curva de aprendizado | Media | UX direta, formularios guiados e dashboard operacional. |
| Suporte violar privacidade do tenant | Alta | `platform_admin` sem acesso default e break-glass auditado. |

## 22. Plano das oito primeiras entregas

| Entrega | Objetivo | Conteudo | Tamanho |
|---|---|---|---|
| E1 | Fundacao conceitual | Documentos desta entrega | M |
| E2 | Base segura executavel | Flutter, env, Supabase, auth, tenant, RLS, shell, testes | GG |
| E3 | Clientes | Clientes, contatos, enderecos, validacoes, RBAC e auditoria | G |
| E4 | Chamados | Chamados, categorias, prioridades, anexos, historico, atribuicao | G |
| E5 | Agenda | Tecnicos, agendamento, conflitos e visitas tecnicas | M |
| E6 | Orcamentos | Itens, calculo server-side, versao, PDF, link e aprovacao | GG |
| E7 | OS | Conversao idempotente, execucao, horas, materiais, despesas, fotos, aceite | GG |
| E8 | Financeiro minimo e deploy | Recebimento manual, recibo, dashboard minimo, staging e smoke tests | G |

## 23. Estimativa relativa

| Tamanho | Criterio |
|---|---|
| P | Pequeno, ate uma sessao, baixo risco, sem grande impacto de dados. |
| M | Medio, uma a duas sessoes, exige validacao e testes focados. |
| G | Grande, varias superficies, exige migration, RLS, UI, testes e docs. |
| GG | Muito grande, fluxo critico ponta a ponta, concorrencia, seguranca ou operacao em staging. |

Estas estimativas nao representam prazo fechado. Elas assumem uma execucao incremental por uma pessoa/agente senior com acesso ao repositorio, testes e ambiente local. Calendario real depende de credenciais, disponibilidade de staging, validacao de produto, revisoes de seguranca e eventuais ajustes de UX.

## 24. Decisoes que precisam ser registradas como ADR

Ja registradas:

- ADR-001: monolito modular sobre Supabase.
- ADR-002: multitenancy por linha com `tenant_id` e RLS.
- ADR-003: regras criticas server-side.
- ADR-004: repositorio unico.
- ADR-005: links publicos com token hasheado.
- ADR-006: versionamento de orcamento por snapshot imutavel.
- ADR-007: conversao orcamento para OS idempotente.
- ADR-008: moeda em `numeric`, nunca `float`.
- ADR-009: PDF via Edge Function no MVP.
- ADR-010: conflito de agenda por funcao transacional provisoria.
- ADR-011: fiscal como abstracao.
- ADR-012: WhatsApp por deep link e registro manual no MVP.
- ADR-013: pagamento manual conciliavel no MVP.
- ADR-014: auditoria INSERT-only.
- ADR-015: `platform_admin` sem acesso default a tenant.
- ADR-016: estoque fora do MVP.
- ADR-017: tipo monetario em Dart com `int` em centavos no MVP.
- ADR-018: testes RLS via SQL e Supabase CLI local.
- ADR-021: autenticacao do MVP por e-mail e senha.
- ADR-022: MVP generico por vertical, com configuracao por tenant.
- ADR-023: direcao visual moderna/neomorfica com acessibilidade obrigatoria.

Pendentes previstos:

- ADR-019: motor de PDF definitivo.
- ADR-020: politica de custo de estoque.

## 25. Perguntas estritamente bloqueadoras

Nenhuma pergunta bloqueia a Entrega 1.

Premissas adotadas para permitir progresso:

- Nome ServiceFlow e provisorio e devera ser configuravel por tenant no futuro.
- Idioma inicial e pt-BR.
- Moeda inicial e BRL.
- Timezone padrao por tenant: `America/Sao_Paulo`, com armazenamento em UTC.
- Impostos no MVP serao informados/controlados, sem motor fiscal automatico.
- Pagamentos no MVP serao manuais e conciliaveis.
- WhatsApp no MVP usa link/manual, sem API nao oficial.
- Hostinger hospeda o frontend estatico; Supabase e o backend principal.
- Requisitos do MVP sao genericos para field service; especializacoes entram via categoria, catalogo e configuracoes.
- Roles iniciais ficam restritas a lista definida na matriz.
- Estilo visual aprovado: moderno, futurista e neomorfico, com contraste e acessibilidade preservados.

## 26. Criterio de conclusao desta entrega

Entrega 1 concluida quando este documento e os documentos de suporte estiverem no repositorio, sem criacao de modulos avancados, e `PROJECT_STATE.md` registrar que a documentacao de fundacao foi consolidada.

# Product

<!-- impeccable:product-schema 1 -->

## Platform

web

## Users

**Dono/gestor** (persona: Carlos, eletricista com 4 funcionários) — papel `tenant_owner`. Trabalha no desktop, entre uma obra e outra. Quer saber o que está aberto, o que foi orçado e o que entrou. Hoje perde orçamento no WhatsApp e não sabe a margem real.

**Analista/atendente** (Juliana) — papel `analyst`/`dispatcher`. Passa o dia na tela: registra chamado, agenda, acompanha. É quem mais sofre com retrabalho e informação espalhada. É a usuária de maior volume de interação do sistema.

**Técnico de campo** (Marcos) — papel `technician`. Celular, na rua, rede instável. Vê a agenda, executa a OS, registra horas, materiais e evidências. Hoje usa papel e foto solta na galeria.

**Financeiro** (Ana) — papel `financial_operator`. Recebe, concilia, cobra inadimplente.

**Parceiro terceirizado** — papel `partner`. Recebe OS, executa, recebe repasse. Modelado no banco desde a 0053: existe como `service_professionals` sem `linked_user_id`, ou seja, pode ser agendado sem ter conta no sistema.

**Cliente final** (Sr. Roberto; síndica de condomínio) — não tem conta e não quer criar uma. Chega pelo link público do orçamento ou da pesquisa de satisfação. É a única audiência que encontra o produto sem treinamento, sem contexto e frequentemente pelo celular, a partir de uma mensagem de WhatsApp.

**Admin da plataforma** — papel `platform_admin`. Opera o SaaS e dá suporte sem violar o isolamento entre empresas.

## Product Purpose

SaaS multiempresa brasileiro para o ciclo completo de serviço técnico em campo: do primeiro contato do cliente até o pagamento, o repasse e a pesquisa de satisfação.

Sucesso é uma empresa pequena conseguir, **no mesmo dia da adesão**, cadastrar um cliente, abrir um chamado, orçar, aprovar por link, executar a OS no celular e receber — sem planilha e sem WhatsApp desorganizado.

## Positioning

O que um concorrente vizinho não copiaria de forma honesta:

- **Aprovação de orçamento por link seguro, sem conta.** O cliente decide em um clique a partir do WhatsApp. O link é tokenizado, tem validade, registra acesso e alimenta o mesmo histórico de aprovação do fluxo interno.
- **Encadeamento comercial → operacional → financeiro com rastreabilidade ponta a ponta.** Aprovou o orçamento, a OS nasce sozinha (trigger de banco, migration 0056), o chamado acompanha o status, e cada passo grava evento auditável. Não é integração entre módulos: é uma cadeia só.
- **Isolamento multiempresa desde a primeira migration.** RLS em todas as tabelas, `current_tenant_id()`, testes de isolamento versionados junto com cada migration.

## Operating Context

- **Dois ambientes de uso simultâneos.** Escritório (desktop, muitas abas, teclado) e campo (celular, sol, uma mão livre, rede ruim). A mesma OS é lida pelos dois.
- **O WhatsApp é o canal real do mercado.** Orçamento e link de aprovação saem por lá. O produto não substitui o WhatsApp: ele entra nele.
- **Chamado é a unidade de entrada.** Chega por telefone, WhatsApp, e-mail ou formulário e vira `service_request`. Pode virar visita, orçamento, OS — ou morrer no caminho, o que também precisa ser registrado.
- **Agenda como quadro de trabalho.** A fila é por categoria profissional: os chamados aparecem para todos os profissionais da categoria, e agendar para um remove da fila dos outros.
- **Vocabulário fixo do domínio, em português.** Chamado, orçamento, OS (ordem de serviço), desagendar, aceite, repasse, tenant/empresa. Esses termos são os que o usuário fala; a interface não os traduz nem os suaviza.

## Capabilities and Constraints

**Stack:** Flutter (web como alvo primário) + Riverpod + GoRouter com hash routing; Supabase/PostgreSQL com RLS e RPCs `SECURITY DEFINER`.

**Confirmado e em produção:** autenticação, tenant, RBAC, auditoria; clientes PF/PJ/condomínio; chamados; agenda com fila por categoria, arrastar-e-soltar e rastreabilidade em `appointment_events`; orçamento com versionamento, planilha de itens por natureza, PDF e link público; conversão automática para OS; execução da OS (horas, materiais, evidências, despesas, aceite); estoque; compras; contas a pagar; DRE.

**Restrições que o design não pode ignorar:**

- Toda ação sensível passa por RPC com verificação de permissão. A interface **nunca** deve oferecer um caminho que o banco vai recusar — botão visível sem permissão é defeito, não detalhe.
- O estado é assíncrono por natureza (`AsyncValue`): toda tela tem estado de carregando, vazio e erro. Erro genérico que esconde a causa já custou caro neste projeto mais de uma vez.
- Fluxos com dinheiro e com status encadeado precisam de confirmação explícita e de desfazer quando existir (`desagendar`, `cancelar OS`, `reabrir orçamento`).
- Link público roda como `anon`: sem sessão, sem tenant no contexto, sem navegação para o resto do app.

**Explicitamente indeciso:** nome comercial definitivo (ServiceFlow é provisório); profundidade da personalização visual por tenant além de nome, logotipo e cor de destaque.

## Brand Commitments

- Identidade própria do produto **com white-label leve por empresa**: cada tenant configura nome, logotipo e cor. A estrutura visual, a tipografia e o comportamento permanecem do ServiceFlow.
- Consequência direta: **nenhuma decisão de design pode depender do roxo atual**. A cor de destaque é uma variável do tenant. Hierarquia, peso e espaçamento têm que sustentar a interface com qualquer paleta.
- Domínio de publicação: `serviceflow.leonardoperescouto.com`.
- Voz em português do Brasil, direta, no vocabulário do prestador de serviço. Sem jargão de software na interface.

## Evidence on Hand

- Documentação de produto e arquitetura em `docs/` (VISION, ARCHITECTURE, DATA_MODEL, ROADMAP, DECISIONS, PROJECT_STATE, CHANGELOG).
- Código de produção do app em `lib/features/**` e 56 migrations versionadas com rollback e teste de isolamento em `supabase/`.
- **Não existe ainda:** pesquisa com usuário real, teste de usabilidade, base de clientes em produção, métrica de uso. Nenhum trabalho futuro deve inventar depoimento, número de clientes, benchmark ou resultado de campo.

## Product Principles

1. **A cadeia não se quebra.** Chamado, orçamento, OS e financeiro são um fluxo só. Toda tela deve deixar claro de onde o item veio e para onde ele vai.
2. **O estado do trabalho é a informação principal.** Antes de qualquer ornamento: em que status está, de quem é, e qual é a próxima ação.
3. **Uma ação principal por vez.** Cada tela tem uma próxima ação óbvia conforme o status; o resto é secundário e pode estar recolhido.
4. **O cliente final não tem treinamento.** As superfícies públicas se explicam sozinhas, em uma tela, sem vocabulário interno.
5. **A marca é variável; a estrutura não.** A interface tem que continuar legível e hierarquizada quando a cor do tenant muda.

## Accessibility & Inclusion

Meta declarada: **WCAG 2.1 AA**. Contraste, alvos de toque e navegação por teclado tratados como requisito de aceite, não como polimento.

Necessidade específica de usuário confirmada: o técnico de campo opera no celular, sob sol e às vezes com uma mão só — o que torna alvo de toque e contraste requisitos operacionais, não apenas de conformidade.

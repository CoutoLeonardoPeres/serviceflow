# ServiceFlow — Arquitetura

## 1. Estilo arquitetural

**Monólito modular** — um único app Flutter (web + Android + iOS preparado) sobre Supabase (PostgreSQL + Auth + RLS + Storage + Edge Functions). Sem microserviços. Módulos com limites lógicos claros dentro do monólito; extração futura possível, não antecipada.

### Stack

| Camada | Tecnologia | Observação |
|---|---|---|
| Frontend | Flutter estável, Dart null safety, Material 3 | Web + Android; iOS preparado |
| Estado | Riverpod | Providers por feature |
| Rotas | GoRouter | Guards de auth/RBAC |
| Modelos | Freezed + json_serializable | Onde agregam valor |
| Backend | Supabase: PostgreSQL, Auth, RLS, Storage, Edge Functions | Regras críticas no banco/Edge |
| Hospedagem web | Hostinger (estática) | SPA + headers de segurança |
| VPS Hostinger | Somente com necessidade objetiva | Nenhuma prevista até F8 |

Autenticação inicial: e-mail e senha via Supabase Auth. Provedores OAuth, SSO/SAML e login social ficam fora do MVP, mas podem ser adicionados depois sem troca da fundação de identidade.

### Ambientes

`development` (Supabase local ou projeto dev), `staging`, `production` — projetos Supabase separados, variáveis via `--dart-define`/arquivos de ambiente fora do Git.

Staging é parte do critério de aceite do MVP e da Entrega 8. Até lá, a arquitetura deve deixar deploy e variáveis preparados; credenciais, domínio e contas reais são dependências operacionais do projeto.

### Direção visual

UI moderna e futurista com neomorfismo controlado: superfícies claras, sombras suaves, botões elevados, acento violeta/azul, microinterações curtas e foco em legibilidade. Em telas internas, a densidade operacional prevalece sobre composição de landing page; o estilo aparece nos controles, filtros, cards de resumo, shell e estados de feedback sem prejudicar contraste, foco de teclado ou acessibilidade.

## 2. Módulos (32)

Fases entre parênteses. MVP = F0–F1.

| # | Módulo | Fase | # | Módulo | Fase |
|---|---|---|---|---|---|
| 1 | Identidade e acesso | F0 | 17 | Fornecedores | F3 |
| 2 | Tenant/empresa | F0 | 18 | Financeiro | F1 básico / F4 |
| 3 | Assinaturas e planos | F2+ | 19 | Pagamentos | F1 manual / F8 |
| 4 | Usuários e equipes | F0/F1 | 20 | Fiscal | F8 (abstração F1) |
| 5 | Clientes | F1 | 21 | Parceiros | F5 |
| 6 | Contatos | F1 | 22 | Comissões/repasses | F5 |
| 7 | Endereços | F1 | 23 | Contratos | F6 |
| 8 | Chamados | F1 | 24 | Preventivas | F6 |
| 9 | Agenda | F1 | 25 | Frota | F7 |
| 10 | Visitas técnicas | F1 | 26 | Despesas | F1 (na OS) / F2 |
| 11 | Orçamentos | F1 | 27 | Comunicação | F1 manual / F8 |
| 12 | Ordens de Serviço | F1 | 28 | Satisfação | F2+ |
| 13 | Apontamento de horas | F1 | 29 | Relatórios | F2 |
| 14 | Materiais (catálogo) | F1 | 30 | Indicadores | F1 mínimo / F9 |
| 15 | Estoque | F3 | 31 | Auditoria | F0 |
| 16 | Compras | F3 | 32 | Administração SaaS | F0 mínimo |

## 3. Camadas (feature-first)

```
lib/
  core/            # tema, rotas, env, erros, formatters, widgets base
  features/<nome>/
    presentation/  # telas, widgets, controllers Riverpod
    application/   # use cases / services
    domain/        # entidades, value objects, contratos
    data/          # repositórios Supabase, DTOs
  shared/          # providers de abstração (Notification, Payment, Fiscal, Maps, Storage)
```

Regras: presentation não acessa tabelas diretamente (sempre via repository); dependências apontam para dentro (data→domain, application→domain); sem dependências circulares; interfaces só onde houver desacoplamento real (providers externos, testes); CRUD simples não ganha camadas extras.

**Regras críticas ficam no banco/Edge Functions**, não no Flutter: cálculo financeiro do orçamento, transições de estado, conversão orçamento→OS, movimentos de estoque, numeração sequencial por tenant, aprovação por link público.

## 4. Diagrama textual de componentes

```
[Flutter Web/Android/iOS]
   │  (anon key + JWT do usuário)
   ├──► [Supabase Auth]  login, recuperação, convites, sessões
   ├──► [PostgREST → PostgreSQL]  CRUD sob RLS por tenant
   │        ├── funções SQL (SECURITY DEFINER mínimas): current_tenant_id(),
   │        │   has_permission(), transições de estado, next_sequence()
   │        ├── triggers: updated_at, auditoria, histórico de status
   │        └── RLS: deny by default em todas as tabelas
   ├──► [Supabase Storage]  buckets por finalidade, paths tenant_id/...,
   │        policies por membership, URLs assinadas temporárias
   └──► [Edge Functions]  (service role, nunca no cliente)
            ├── quote-public: exibir/aprovar orçamento via token de link
            ├── quote-convert: conversão idempotente orçamento→OS
            ├── pdf-generate: geração e armazenamento de PDF versionado
            ├── invite-accept: aceite de convite
            └── (F8) webhooks de pagamento/WhatsApp/fiscal

[Cliente final] ──► páginas públicas Flutter Web ──► Edge Functions (token hasheado, rate limit)
[Hostinger] hospeda o build web estático; nenhum segredo no bundle.
```

## 5. Providers de abstração (interfaces em `shared/`)

`NotificationProvider`, `WhatsAppProvider` (MVP: deep link `wa.me` + registro manual), `EmailProvider` (MVP: Supabase/SMTP transacional simples), `PaymentProvider` (MVP: registro manual), `FiscalProvider` (MVP: no-op + registro de solicitação), `MapsProvider` (MVP: link externo), `StorageProvider` (Supabase Storage). Outbox de mensagens desde a F2 para envio com retentativa/backoff.

## 6. Decisões estruturais (resumo — ver DECISIONS.md)

Repositório único (app Flutter + /supabase + /docs + /scripts + /tests); sem monorepo multi-app até existir segundo app. Realtime somente onde necessário (ex.: status de OS na agenda) — não por padrão. Consultas analíticas via views; materialized views só quando volume justificar.

## 7. Riscos técnicos

| Risco | Impacto | Mitigação |
|---|---|---|
| Erro de policy RLS vazando dados entre tenants | Crítico | Deny by default, testes automatizados de isolamento por tabela, revisão de toda função SECURITY DEFINER |
| Links públicos como superfície de ataque | Alto | Token aleatório ≥256 bits, hash no banco, expiração, escopo mínimo, rate limit, auditoria |
| Cálculo financeiro divergente cliente×servidor | Alto | Fonte da verdade no servidor; Flutter apenas pré-visualiza |
| Limites de Edge Functions (timeout, cold start) p/ PDF | Médio | PDFs simples no MVP; medir; VPS só se comprovadamente necessário |
| Flutter Web: SEO/tamanho de bundle nas páginas públicas | Médio | Páginas públicas mínimas; aceitar trade-off no MVP; reavaliar na F2 |
| Concorrência (dupla aprovação, duplo consumo) | Alto | Idempotency keys, constraints únicas, transações, locks otimistas |
| Migrations destrutivas | Alto | Expand-and-contract obrigatório; validação no CI |
| Suporte iOS atrasar por conta de plugins | Baixo | Escolher dependências com suporte às 3 plataformas |

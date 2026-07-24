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

## A registrar nas próximas entregas
- ADR-019: motor de PDF (lib Dart em Edge/Deno vs serviço) (E6).
- ADR-020: política de custo de estoque — custo médio vs última compra (F3).

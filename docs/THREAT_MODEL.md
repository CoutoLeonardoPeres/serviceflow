# ServiceFlow — Modelo de Ameaças (STRIDE)

Ativos protegidos: dados pessoais de clientes (LGPD), dados financeiros por tenant, credenciais/sessões, links públicos de aprovação, evidências/anexos, integridade de orçamentos/OS/estoque/pagamentos, trilha de auditoria.

Superfícies: app Flutter (web/mobile), PostgREST sob RLS, Edge Functions, páginas públicas com token, Storage, Auth, (F8) webhooks.

## S — Spoofing

| Ameaça | Vetor | Mitigação |
|---|---|---|
| Sessão roubada/reutilizada | XSS, dispositivo compartilhado | JWT curto + refresh revogável, logout global, expiração de sessão |
| Enumeração de usuários | Respostas distintas em login/recuperação | Mensagens genéricas, rate limit, timing uniforme |
| Falsidade em link público | Adivinhação/força bruta de token | Token ≥256 bits CSPRNG, hash (SHA-256) no banco, expiração, rate limit por IP+token, revogação |
| Aprovação por terceiro não autorizado | Link encaminhado | OTP/confirmação parcial de dado para ações críticas; registro de IP/user-agent proporcional |
| Webhook forjado (F8) | Endpoint público | Assinatura + timestamp + replay window + event_id idempotente |

## T — Tampering

| Ameaça | Vetor | Mitigação |
|---|---|---|
| Alteração de valores de orçamento pelo cliente | Payload manipulado no Flutter | Cálculo server-side; totais recalculados no banco; Flutter só pré-visualiza |
| Manipulação de tenant_id | Request adulterado | tenant_id derivado do JWT/membership no servidor; nunca aceito do cliente |
| Alteração direta de saldo de estoque | Update em stock_balances | Saldo somente via movimentos; sem UPDATE direto (revoke + trigger) |
| Edição de orçamento já enviado | Update pós-envio | Imutabilidade após envio; alterações geram nova versão |
| Adulteração de PDF | Substituição de arquivo | Checksum + versão + bucket write-once por convenção + URL assinada |
| Transição de estado inválida | Chamada direta à API | Máquina de estados no banco (função + trigger), papéis autorizados por transição |

## R — Repudiation

| Ameaça | Mitigação |
|---|---|
| "Não aprovei esse orçamento" | Registro de aprovação: versão aprovada, timestamp, canal, IP proporcional, user-agent, OTP quando usado |
| "Não alterei esse dado" | audit_logs com actor, ação, entidade, before/after seguro, request_id |
| Suporte da plataforma nega acesso indevido | Acesso platform_admin a conteúdo de tenant somente via fluxo autorizado + auditado |

## I — Information Disclosure

| Ameaça | Vetor | Mitigação |
|---|---|---|
| Vazamento horizontal entre tenants | Policy RLS incorreta | RLS deny-by-default em toda tabela; testes automatizados A↛B por tabela; revisão de SECURITY DEFINER com search_path fixo |
| Vazamento vertical (técnico vê financeiro) | Falta de checagem de permissão | RBAC no banco + colunas sensíveis via views/policies; UI esconde E servidor nega |
| IDOR em links/arquivos | IDs sequenciais previsíveis | UUIDs externos; Storage por path tenant + policy; URLs assinadas temporárias |
| Segredos no bundle Flutter | service role no cliente | Apenas anon key no cliente; secret scanning no CI |
| Erros expondo schema/SQL | Stack trace ao usuário | Tratamento centralizado; mensagem genérica + request_id |
| Logs com dados sensíveis | Log ingênuo | Proibição de senha/token/cartão em logs; mascaramento |

## D — Denial of Service

| Ameaça | Mitigação |
|---|---|
| Flood em páginas públicas/login | Rate limit (Edge + Auth), CAPTCHA se necessário (pós-MVP) |
| Upload abusivo | Limite de tamanho, allowlist MIME, quota por tenant |
| Consultas pesadas em telas críticas | Paginação server-side obrigatória, índices, views agregadas |
| Esgotamento de Edge Functions (PDF) | PDFs sob demanda com fila simples/backoff; monitorar |

## E — Elevation of Privilege

| Ameaça | Mitigação |
|---|---|
| Usuário se autopromove | Roles somente alteráveis por tenant_owner/admin via função validada; auditoria de mudança de permissão |
| Convite reutilizado/interceptado | Token de convite expirável, uso único, vínculo a e-mail |
| Função SECURITY DEFINER abusada | Mínimas, parâmetros validados, search_path fixo, revisão obrigatória em PR |
| Cliente de link público acessa outros dados | Escopo do token limitado a uma entidade/ação; Edge Function valida escopo a cada chamada |
| platform_admin abusa de acesso | Segregação: sem acesso default a dados de tenant; fluxo break-glass auditado |

## Endpoints anônimos em produção (inventário)

Toda escrita sem autenticação precisa constar aqui. Hoje são dois, ambos via
RPC `SECURITY DEFINER` com token opaco — nunca via PostgREST direto.

| Endpoint | Migration | Escrita | Mitigações ativas | Lacunas aceitas |
|---|---|---|---|---|
| `decide_public_quotation` | 0006 | Decisão de orçamento | Token 256 bits, hash SHA-256, expiração 15d, revogação, escopo de 1 orçamento | Rate limit por IP não implementado |
| `submit_public_satisfaction` | 0041 | Nota de satisfação | Token 256 bits, hash SHA-256, expiração 30d, revogação, escopo de 1 OS, só OS concluída, dados mínimos na leitura | Rate limit por IP não implementado; resposta não é única (permite correção enquanto o link valer) |

**Divergência conhecida do quadro S (linha "Falsidade em link público"):** aquele
quadro prevê *rate limit por IP+token* como mitigação padrão. Nenhum dos dois
endpoints o implementa hoje — exigiria uma Edge Function na frente do RPC.
Decisão registrada em F2-P5; risco residual: um token válido vazado (ex.: print
de WhatsApp encaminhado) permite reenvio/alteração da resposta até expirar.
Impacto limitado a uma OS e sem exposição de dados. **Reavaliar antes do GA.**

Para a pesquisa de satisfação, `get_public_satisfaction_context` devolve apenas
número da OS, título do serviço e nome da empresa. Não expõe valores, endereço,
telefone, e-mail nem qualquer identificador do cliente.

## Testes de segurança obrigatórios (gate de build)

Os 12 testes da especificação (§18): isolamento A↛B leitura/escrita, RBAC técnico×financeiro, cliente×cliente, link expirado/revogado/inválido, upload não autorizado, webhook sem assinatura, idempotência de pagamento/aprovação/consumo.

## Fora de escopo do MVP (registrado)

WAF dedicado, pentest externo (recomendado antes do GA), MFA obrigatório para todos, SIEM. MFA de admins preparado; crash reporting configurável.

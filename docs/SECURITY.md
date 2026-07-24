# ServiceFlow — Segurança

Princípios: security/privacy by design, secure by default, menor privilégio, deny by default, defesa em profundidade, segregação de funções. Referências: OWASP ASVS/Top10/API/MASVS, CWE, LGPD. Ameaças detalhadas: THREAT_MODEL.md.

## 1. Matriz simplificada de papéis × permissões (MVP)

Legenda: C=criar, R=ler, U=atualizar, D=cancelar/desativar, ✱=escopo restrito.

| Recurso | owner | admin | manager | analyst | dispatcher | technician | financial | viewer | cliente (link) |
|---|---|---|---|---|---|---|---|---|---|
| Config. do tenant | CRUD | CRUD | R | – | – | – | – | – | – |
| Usuários/convites | CRUD | CRUD | R | – | – | – | – | – | – |
| Clientes/contatos/endereços | CRUD | CRUD | CRUD | CRUD | R | R✱ | R | R | próprio✱ |
| Catálogo (serviços/materiais/tarifas) | CRUD | CRUD | CRUD | R | R | R | R | R | – |
| Chamados | CRUD | CRUD | CRUD | CRUD | CRU | R✱ atribuídos | R | R | próprio✱ |
| Agenda/visitas | CRUD | CRUD | CRUD | CRU | CRUD | R✱ próprios | – | R | confirmar✱ |
| Orçamentos | CRUD | CRUD | CRUD | CRU | R | – | R | R | ver/aprovar versão✱ |
| Desconto acima do limite | ✔ | ✔ | ✔ (limite) | – | – | – | – | – | – |
| OS | CRUD | CRUD | CRUD | CRU | CRU | RU✱ execução das suas | R | R | acompanhar✱ |
| Horas/materiais/despesas da OS | CRUD | CRUD | CRUD/aprova | R | R | CRU✱ suas | R | – | – |
| Recebimentos/recibos | CRUD | CRUD | R | – | – | – | CRUD | – | R próprio✱ |
| Valores de custo/margem | R | R | R | – | – | – | R | – | nunca |
| Auditoria | R | R | – | – | – | – | – | – | – |

`platform_admin`: administra a plataforma; **sem acesso default** a dados de tenant; acesso de suporte somente via fluxo break-glass autorizado e auditado. `partner`, `warehouse_operator`: fases 5/3. RBAC → evolução ABAC: técnico limitado a OS designadas a ele/sua equipe (policy com join em assignments), parceiro às suas OS, cliente aos próprios registros.

## 2. Controles (MVP)

**Autenticação (Supabase Auth):** confirmação de e-mail configurável; recuperação segura; MFA preparado p/ admins; rate limit de tentativas; mensagens sem enumeração; sessões revogáveis + logout global; bloqueio de usuário via membership.status; convite com token hasheado e expirável; senha jamais em logs.

No MVP, o único provedor de login interativo é e-mail e senha. OAuth social, Google, Facebook, SSO e SAML ficam fora do MVP para reduzir superfície de ataque e complexidade operacional.

**Autorização:** RLS em 100% das tabelas expostas (deny by default); `has_permission(perm)` em policies e funções; tenant derivado do JWT (`current_tenant_id()` via membership ativa); anti-IDOR: UUIDs + policies; colunas sensíveis (custo, margem) via views/policies dedicadas.

**Isolamento de tenants além de RLS:** projetos Supabase separados por ambiente; `tenant_id` gerado/validado server-side; testes automatizados A↛B para leitura e escrita por tabela; Storage por path de tenant com policies; funções `SECURITY DEFINER` mínimas e revisadas; auditoria para ações sensíveis; fluxo break-glass auditado para suporte de plataforma.

**Entrada/saída:** validação dupla (Flutter + servidor/constraints); limites de tamanho; allowlist MIME (`image/jpeg,png,webp`, `video/mp4`, `application/pdf` + office comuns); nomes de arquivo gerados pelo sistema; download somente por URL assinada temporária; sanitização de texto exibido em páginas públicas.

**Links públicos:** token CSPRNG ≥256 bits, somente hash armazenado, expiração, escopo mínimo (uma entidade/versão/ação), revogável, uso único quando apropriado, rate limit, acesso auditado, sem IDs sequenciais; ação crítica (aprovar) pode exigir OTP/confirmação parcial de dado — configurável por tenant.

**Segredos:** nada no Git nem no bundle Flutter; service role apenas em Edge Functions; `.env` fora do versionamento + `.env.example`; secret scanning no CI; rotação e revogação documentadas (INCIDENT_RESPONSE.md na F0).

**Auditoria:** eventos mínimos — login/falha, convite, mudança de permissão, CRUD de cliente, orçamento (criação/envio/aprovação/rejeição), status de OS, financeiro (recebimento/baixa/cancelamento/estorno), emissão de documento, acesso administrativo, exportação, exclusão/anonimização, mudança de configuração. Registro: tenant_id, actor, ação, entidade, entity_id, timestamp, origem, request_id, before/after seguro. Nunca: senha, token, credencial, cartão, CVV. Tabela INSERT-only.

**Financeiro:** valores calculados server-side; sem dados completos de cartão (nunca); confirmação automática de pagamento só via webhook validado (F8); idempotência obrigatória; estorno por permissão; NUMERIC, nunca float.

## 3. LGPD

Bases legais: execução de contrato (dados de clientes p/ prestação de serviço), legítimo interesse (prospecção mínima), obrigação legal (fiscal/financeiro). Implementar no MVP: minimização, aviso de privacidade, controle de acesso, auditoria, exportação de dados do titular (F2), correção, anonimização em vez de exclusão física para registros com obrigação de retenção (financeiro/fiscal/auditoria), registro de aceite nos links públicos, inventário de dados pessoais (docs/, F2), resposta a incidentes (runbook F2). Retenção configurável por tenant (F2+). IP registrado de forma proporcional e documentada.

## 4. Gates de build (CI)

`dart format --set-exit-if-changed` · `flutter analyze` · `flutter test` (incl. testes de RLS/isolamento via banco local) · validação de migrations · secret scan · dependency scan. Os 12 testes de segurança da especificação são bloqueantes a partir da entrega que introduz cada recurso.

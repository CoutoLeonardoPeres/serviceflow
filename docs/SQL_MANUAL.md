# ServiceFlow — Manual SQL e Supabase

Ultima atualizacao: 2026-07-23

## Projeto Supabase atual

- Nome conhecido: `Service_Saas`.
- Project ref: `pkbluscdssiiumrppmwa`.
- Auth usado pelo app: e-mail e senha.
- Chave usada no Flutter: somente `anon key`.
- Nunca colocar `service_role key` no Flutter, no build web, no Git ou em arquivos publicos.

## Owner master permanente

A migration `0063_master_owner_account.sql` promove `leonardopcouto@gmail.com`
como Owner master do ServiceFlow. Ela deve ser aplicada somente no projeto
Supabase correto e com backup recente, pois concede acesso transversal a todas
as empresas.

O Owner master recebe `platform_admin`, `tenant_owner` em todos os tenants e
politicas RLS globais nas tabelas que possuem `tenant_id`. A conta, suas
associacoes e o privilegio master sao protegidos por triggers contra remocao,
suspensao ou downgrade. A senha permanece exclusivamente no Supabase Auth e
nunca e escrita em SQL, logs ou arquivos do projeto.

## Principios de banco

O ServiceFlow e multi-tenant. Cada empresa deve enxergar somente seus proprios dados.

Controles obrigatorios:

- Todas as tabelas de negocio devem ter `tenant_id`, direta ou indiretamente.
- RLS deve ficar habilitado nas tabelas de negocio.
- A empresa ativa do usuario deve ser resolvida no banco.
- Escritas sensiveis devem passar por RPCs com validacao server-side.
- Permissoes devem ser verificadas no banco, nao apenas na tela.
- Storage privado deve validar tenant pelo caminho e/ou metadados.
- Eventos importantes devem gerar auditoria em `audit_logs`.

## Sequencia de migrations

Aplicar sempre em ordem:

| Migration | Conteudo |
|---|---|
| `0001_foundation.sql` | Fundacao: tenants, usuarios, memberships, roles, permissoes, auditoria, funcoes auxiliares e RLS inicial. |
| `0002_customers.sql` | Clientes, contatos, enderecos e ativos/equipamentos. |
| `0003_service_requests.sql` | Chamados, categorias, prioridades, historico, anexos, notas, atribuicoes e Storage de anexos. |
| `0004_scheduling.sql` | Agenda, atribuicoes, visitas tecnicas, evidencias e RPC de agendamento. |
| `0005_quotations.sql` | Orcamentos, versoes, itens, links publicos, aprovacoes e calculo server-side. |
| `0006_quotation_public_flow.sql` | Fluxo publico de orcamento por token opaco e decisoes publicas. |
| `0007_quotation_public_revoke.sql` | Revogacao manual de links publicos ativos. |
| `0008_work_orders.sql` | Ordens de servico, itens, eventos, evidencias e conversao de orcamento aprovado. |
| `0009_work_order_execution.sql` | Horas trabalhadas e materiais aplicados. |
| `0010_work_order_acceptance.sql` | Aceite do cliente na OS. |
| `0011_work_order_expenses.sql` | Despesas operacionais da OS. |
| `0012_work_order_evidence_storage.sql` | Bucket privado e RPC auditado para evidencias da OS. |
| `0013_financials_minimum.sql` | Recebiveis, pagamentos manuais, recibos e RPCs financeiros. |
| `0014_customer_satisfaction.sql` | Pesquisa de satisfacao simples vinculada a OS concluida. |
| `0015_quotation_attachments.sql` | Fotos privadas de orcamentos para catalogo e historico. |
| `0022_tenant_subscription_plans.sql` a `0034_tenant_billing_webhook_events.sql` | Planos SaaS, limites, unidades, membros, convites, onboarding de plano, historico comercial, sessoes de checkout rastreaveis, confirmacao comercial e infraestrutura de webhooks de cobranca. |
| `0064_platform_admin_tenant_overview.sql` | RPC protegida para o painel master listar empresas, plano, cobrança, usuários e unidades sem abrir acesso transversal por RLS. |

Rollbacks correspondentes ficam em `supabase/rollbacks/`.

## Relatorios basicos

A primeira versao de Relatorios nao cria migration nova. A tela `/relatorios` consulta tabelas existentes:

- `customers`
- `service_requests`
- `appointments`
- `quotations`
- `work_orders`
- `receivables`
- `work_order_satisfaction`

Como as consultas usam o cliente Supabase autenticado com `anon key`, a protecao vem do RLS ja existente em cada tabela. Se uma permissao de leitura for removida de algum perfil, a tela deve mostrar erro amigavel em vez de vazar dados.

O filtro de periodo usa `created_at` nas tabelas consultadas. Os recebiveis vencidos continuam sendo identificados por `due_date`, mas somente dentro do conjunto criado no periodo selecionado.

O grafico mensal tambem usa `created_at` para agrupar chamados, OS concluidas e recebiveis pagos por mes. Em uma fase futura, se for necessario medir por data de conclusao/pagamento real, criar views ou RPCs especificas para esse criterio.

O ranking `Clientes em destaque` usa `customer_id` de chamados, OS e recebiveis, com nomes lidos de `customers`. A ordenacao prioriza valor financeiro total e depois quantidade de interacoes.

O ranking `Tipos de servico em alta` usa `category_id` de `service_requests` e nomes de `service_categories`. Chamados sem categoria aparecem como `Sem categoria`.

O ranking `Tecnicos em campo` usa `appointment_assignments.technician_user_id`, `work_order_time_entries.technician_id` e nomes de `profiles.full_name`. Agendamentos revogados sao ignorados.

Os indicadores de satisfacao usam `work_order_satisfaction.rating`, filtrando por `created_at` no periodo selecionado. A tela mostra nota media, quantidade total de avaliacoes e avaliacoes criticas, consideradas como notas 1 ou 2.

Quando os relatorios avancarem para filtros pesados, graficos historicos ou grandes volumes, considerar uma migration nova com views/RPCs agregadas por tenant.

## Recriar banco em um Supabase novo

1. Criar um novo projeto Supabase.
2. Ativar login por e-mail e senha no Supabase Auth.
3. Configurar a CLI do Supabase localmente.
4. Fazer link com o projeto.
5. Aplicar migrations.
6. Criar usuarios reais no Supabase Auth.
7. Atualizar seeds/testes com os UUIDs reais.
8. Validar RLS e Storage.
9. Atualizar `dart_defines/dev.json` ou `staging.json` com URL e anon key do novo projeto.

Comandos base:

```bash
supabase link --project-ref SEU_PROJECT_REF
supabase migration list
supabase db push
supabase migration list
```

Se for necessario aplicar SQL manualmente, use a ordem dos arquivos em `supabase/migrations/`.

## Seeds

Arquivo:

```text
supabase/seed/dev_seed.sql
```

Antes de rodar seed:

- Criar usuarios reais no Supabase Auth.
- Copiar os UUIDs reais dos usuarios.
- Substituir os UUIDs ficticios do seed.
- Garantir que existe pelo menos um usuario administrador e um tecnico ativo.

## Funcoes importantes

Funcoes de fundacao:

- `current_tenant_id()`
- `has_permission(...)`
- `next_sequence(...)`

RPCs principais:

- `create_tenant(...)`
- `schedule_appointment(...)`
- `list_tenant_technicians(...)`
- `create_quotation(...)`
- `create_quotation_public_link(...)`
- `get_public_quotation(...)`
- `decide_public_quotation(...)`
- `revoke_quotation_public_links(...)`
- `convert_approved_quotation_to_work_order(...)`
- `transition_work_order(...)`
- `record_work_order_time_entry(...)`
- `add_work_order_material(...)`
- `record_work_order_acceptance(...)`
- `add_work_order_expense(...)`
- `record_work_order_evidence(...)`
- `create_receivable_from_work_order(...)`
- `register_manual_payment(...)`
- `record_work_order_satisfaction(...)`

## Storage

Buckets atuais:

- `service-request-attachments`: anexos de chamados.
- `quotation-attachments`: fotos privadas de orcamentos.
- `work-order-evidence`: evidencias privadas de OS.

Regras:

- Buckets de evidencias e anexos devem ser privados.
- Caminhos devem carregar o tenant quando usado nas policies.
- Upload deve validar permissao e tenant.
- A aplicacao nao deve depender de URL publica permanente para arquivos privados.

## Testes SQL de isolamento

Roteiros ficam em:

```text
test/isolation/
```

Esses testes precisam de usuarios/UUIDs reais. Nao rode os scripts sem substituir placeholders ou dados ficticios.

Roteiros atuais:

- `rls_isolation_test.sql`
- `0002_rls_customers_test.sql`
- `0003_rls_service_requests_test.sql`
- `0004_rls_scheduling_test.sql`
- `0005_rls_quotations_test.sql`
- `0006_public_quotation_link_test.sql`
- `0007_work_orders_test.sql`
- `0008_work_order_execution_test.sql`
- `0009_work_order_acceptance_test.sql`
- `0010_work_order_expenses_test.sql`
- `0011_work_order_evidence_storage_test.sql`
- `0012_financials_minimum_test.sql`
- `0013_customer_satisfaction_test.sql`

## Preflight de seguranca

Antes de publicar:

```bash
./scripts/security_preflight.sh dist/serviceflow-staging.zip --remote
```

Esse script verifica:

- Se arquivos de ambiente nao foram empacotados.
- Se padroes de segredo nao aparecem no bundle.
- Se o pacote `.zip` nao contem arquivos indevidos.
- Se existem rollbacks para as migrations.
- Se as migrations remotas estao alinhadas quando `--remote` e usado.

## Checklist ao criar nova migration

1. Criar arquivo novo em `supabase/migrations/NNNN_nome.sql`.
2. Criar rollback correspondente em `supabase/rollbacks/NNNN_nome_rollback.sql`.
3. Habilitar RLS em novas tabelas de negocio.
4. Criar policies por tenant.
5. Validar permissoes dentro de RPCs.
6. Gerar auditoria para eventos relevantes.
7. Criar roteiro em `test/isolation/`.
8. Atualizar `docs/SQL_MANUAL.md`.
9. Atualizar `docs/PROJECT_STATE.md`.
10. Atualizar `docs/RECREATE_PROMPT.md` se a migration for essencial para reconstruir o sistema.

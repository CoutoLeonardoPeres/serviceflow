# Fase 1 — Runbook de Validação de Segurança (RLS)

**Preparado em:** 2026-07-24 · **Objetivo:** validar que o isolamento entre tenants é real, sem vazamento de dados, antes de publicar em staging (critério bloqueador do MVP).

Este runbook foi preparado a partir do sandbox de análise, que **não tem acesso à internet para o Supabase** (`supabase.co` bloqueado pelo firewall) nem ao Supabase CLI/psql instalados. Todos os comandos abaixo devem ser executados na sua máquina local, com acesso real ao projeto Supabase `Service_Saas` (`pkbluscdssiiumrppmwa`).

---

## ⚠️ Aviso importante: testes reescritos ainda não foram executados

Os 7 arquivos `0007`–`0013` foram **reescritos do zero** nesta sessão (a versão anterior era um roteiro manual comentado, sem valor de teste real). Eles foram revisados linha a linha contra as assinaturas exatas das funções SQL nas migrations `0008`–`0014`, mas **nunca foram executados** — este sandbox de análise não tem PostgreSQL nem acesso root para instalar (`apt-get` bloqueado por permissão). Trate-os como "prontos para primeira execução", não como "testados".

**Recomendação:** rode-os primeiro contra um Supabase local (`supabase start`, banco descartável) antes de apontar para o projeto remoto `Service_Saas`, para pegar qualquer erro de sintaxe ou de sequência de chamadas sem risco:

```bash
supabase start
supabase db reset   # aplica as migrations 0001-0035 do zero localmente
export DATABASE_URL="postgresql://postgres:postgres@127.0.0.1:54322/postgres"
# repita T1.2-T1.4 apontando para este banco local antes de ir para o remoto
```

Se algum teste falhar por erro de sintaxe/lógica (não por vazamento real de isolamento), é provável que seja um ajuste pontual no arquivo `.sql` — não necessariamente um problema de segurança do produto. Corrija e reexecute antes de interpretar como falha de RLS.

## O que foi preparado nesta sessão (sem execução real)

1. **Migrations confirmadas**: sequência `0001`–`0035` contígua, sem duplicatas (colisão `0034` corrigida na Fase 0).
2. **`supabase/seed/dev_seed.sql` reescrito**: cria 2 tenants (Alpha/Beta) e 5 usuários de teste com papéis reais (`tenant_owner`, `technician`, `viewer`, `analyst`), usando placeholders de UUID sintaticamente válidos e consistentes com todos os arquivos de teste.
3. **12 dos 13 roteiros de `test/isolation/*.sql` foram reescritos** (`0002`–`0013`, exceto `0006`): a versão anterior de `0007` a `0013` era um roteiro manual comentado, sem asserção automática nem checagem de isolamento entre tenants. Agora todos seguem o mesmo padrão de `0002`–`0005`: blocos `DO $$ ... $$` com `RAISE EXCEPTION` em caso de falha, verificação de isolamento cross-tenant, e rollback automático dos dados de teste ao final.
4. **3 scripts novos** para automatizar a execução:
   - `scripts/create_test_users.sh` — cria os 5 usuários via Supabase Auth Admin API.
   - `scripts/apply_test_uuids.sh` — substitui os placeholders pelos UUIDs reais e gera cópias prontas em `test/_generated/` (gitignored).
   - `scripts/run_isolation_tests.sh` — roda todos os testes gerados em sequência e produz relatório PASS/FAIL.

---

## T1.1 — Confirmar migrations aplicadas no Supabase remoto

```bash
supabase login
supabase link --project-ref pkbluscdssiiumrppmwa
supabase migration list
```

Confirme que a lista mostra `0001` até `0035` como aplicadas (`Applied`) e nenhuma pendente. Se `0035` (renomeada nesta sessão) ainda não foi aplicada remotamente, aplique:

```bash
supabase db push
```

---

## T1.2 — Criar usuários de teste

Você precisa da **service_role key** do projeto (Supabase Dashboard > Settings > API > `service_role`). Nunca coloque essa chave em `dart_defines/` ou em qualquer arquivo commitado.

```bash
export SUPABASE_URL="https://pkbluscdssiiumrppmwa.supabase.co"
export SUPABASE_SERVICE_ROLE_KEY="<cole a service_role key aqui>"
./scripts/create_test_users.sh
```

O script cria 5 usuários (`alpha_owner`, `alpha_tech`, `alpha_viewer`, `alpha_analyst`, `beta_owner`) e imprime os UUIDs reais gerados pelo Supabase Auth. **Anote esses 5 UUIDs** — você vai precisar deles no próximo passo.

---

## T1.3 — Aplicar o seed e obter os tenant_id reais

```bash
psql "$DATABASE_URL" -f supabase/seed/dev_seed.sql
psql "$DATABASE_URL" -c "SELECT slug, id FROM tenants WHERE slug IN ('empresa-alpha','beta-refrigeracao');"
```

Anote os 2 `tenant_id` retornados (Alpha e Beta).

> `$DATABASE_URL` é a connection string direta do Postgres (Supabase Dashboard > Settings > Database > Connection string > **URI**, não o pooler — os testes usam `SET LOCAL role` e `set_config` em transação, que exigem conexão direta).

---

## T1.4 — Gerar e rodar os 12 testes automatizados

Com os 5 UUIDs de usuário (T1.2) e os 2 UUIDs de tenant (T1.3) em mãos:

```bash
export TENANT_ALPHA="<uuid do tenant empresa-alpha>"
export TENANT_BETA="<uuid do tenant beta-refrigeracao>"
export USER_ALPHA="<uuid do alpha_owner>"
export USER_BETA="<uuid do beta_owner>"
export USER_TECH="<uuid do alpha_tech>"
export USER_VIEWER="<uuid do alpha_viewer>"

./scripts/apply_test_uuids.sh
./scripts/run_isolation_tests.sh "$DATABASE_URL"
```

O runner imprime `PASSOU`/`FALHOU` por arquivo e salva um relatório completo em `test_results_isolation_<data>.txt` (gitignored — não commitar, contém UUIDs reais do seu ambiente).

**Se qualquer teste falhar, pare aqui.** Não prossiga para a Fase 2 (publicação em staging) até identificar e corrigir a causa — isolamento entre tenants é o critério de segurança mais crítico do MVP.

### Teste manual restante: 0006 (link público de orçamento)

Este teste não foi incluído no runner automático porque depende de um orçamento aprovado real (não vem do seed). Rode manualmente após criar um orçamento e aprová-lo (via app ou SQL direto):

```bash
psql "$DATABASE_URL" -v USER_UUID_COM_QUOTATIONS_SEND="'$USER_ALPHA'" \
  -v QUOTATION_UUID="'<uuid de um orcamento aprovado>'" \
  -f test/isolation/0006_public_quotation_link_test.sql
```

(Ajuste o arquivo para usar `\set` se preferir, seguindo o mesmo padrão dos demais — atualmente ele usa placeholders `<...>` que precisam ser editados diretamente no arquivo antes de rodar.)

### Teste complementar: rls_isolation_test.sql

Este arquivo é mais antigo e testa invariantes do schema (membership, unicidade de slug, `next_sequence`) por consulta direta, **não** simula JWT/RLS como os demais. É um complemento rápido, não substitui os 12 testes principais. Rode com:

```bash
psql "$DATABASE_URL" -f test/isolation/rls_isolation_test.sql
```

---

## T1.5 — Security preflight remoto

```bash
./scripts/security_preflight.sh dist/serviceflow-staging-dry-run.zip --remote
```

Deve terminar com `OK: security check passed`. Isso confirma: nenhuma chave administrativa no bundle, pacote sem segredos, migrations locais alinhadas com o remoto, rollbacks presentes.

---

## T1.6 — Conferir auditoria

Após rodar os testes (que geram e revertem dados de teste), confirme que a auditoria capturou as operações antes do rollback — isso já é verificado dentro de cada teste (blocos `T12`, `T5`, `T6`, `T7` conforme o arquivo), mas você pode confirmar manualmente que a tabela está ativa em produção real:

```sql
SELECT action, entity, created_at
FROM audit_logs
ORDER BY created_at DESC
LIMIT 20;
```

---

## Checklist de saída da Fase 1

- [ ] `supabase migration list` mostra `0001`–`0035` aplicadas, nenhuma pendente
- [ ] 5 usuários de teste criados (`create_test_users.sh`)
- [ ] Seed aplicado, 2 tenants criados, UUIDs anotados
- [ ] `run_isolation_tests.sh` reporta `Falhas: 0` para os 12 testes automatizados
- [ ] Teste manual `0006` (link público) executado e passou
- [ ] `security_preflight.sh --remote` retornou OK
- [ ] Auditoria confirmada ativa

Quando todos os itens acima estiverem ✅, a Fase 1 está concluída e o projeto pode avançar para a **Fase 2 (publicação em staging)**.

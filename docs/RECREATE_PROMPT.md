# ServiceFlow — Prompt Mestre de Reconstrucao

Ultima atualizacao: 2026-07-22

Use este prompt quando precisar recriar o ServiceFlow do zero com Codex ou outro agente de desenvolvimento.

```text
Voce e uma equipe senior multidisciplinar de produto, arquitetura, seguranca, UX/UI, Flutter, Supabase/Postgres, QA e deploy. Recrie o sistema ServiceFlow como um SaaS web para gestao de empresas de servicos tecnicos em campo.

Idioma do produto: portugues do Brasil.

Objetivo:
Criar um MVP funcional para empresas genericas de servicos tecnicos, como eletricistas, encanadores, tecnicos de refrigeracao, manutencao predial e assistencias. Nao especializar demais por vertical no MVP, mas manter modelo extensivel.

Stack obrigatoria:
- Flutter Web.
- Riverpod para estado.
- GoRouter para rotas.
- Supabase Auth, Database, RPCs, RLS e Storage.
- Login somente por e-mail e senha.
- Build web estatico para publicacao em Apache/Hostinger.

Direcao visual:
- Design moderno, futurista e claro.
- Neomorphism/neomorfismo com relevos, sombras suaves, bordas arredondadas e superficie acinzentada.
- Acoes primarias em roxo/indigo.
- Usar popups para cadastros e criacoes: novo cliente, novo chamado, novo agendamento, novo orcamento, nova OS, baixa manual, horas, materiais, despesas, evidencias e aceite.
- Em telas e popups de cadastro, organizar campos lado a lado quando houver largura, seguindo secoes neomorficas com relevo; quebrar para uma coluna apenas quando a largura nao comportar.
- No popup de novo cliente, incluir pessoa de contato principal preenchida inicialmente com o nome do cliente e telefone preenchido inicialmente com o telefone do cliente, mas ambos editaveis; incluir endereco padrao obrigatorio com CEP primeiro, preenchimento automatico de rua, bairro, cidade e UF via consulta de CEP e botao `Localizar` para salvar latitude/longitude do endereco.
- Na lista e na tela de detalhe de clientes, exibir botao visivel `Editar cliente` para abrir a edicao cadastral em popup.
- Evitar tela branca no primeiro carregamento; criar splash/loading neomorfico.
- Agenda mensal parecida com a referencia do usuario: menu lateral, barra superior, grade mensal, navegacao para esquerda/direita, estados livre/ocupado/fechado, periodos manha/tarde/noite e popup ao clicar no dia.
- Chamados aceitam fotos no cadastro. Orcamentos e OS aceitam fotos e documentos no cadastro e no historico, incluindo PDF e arquivos Office comuns.

Seguranca obrigatoria:
- Sistema multi-tenant.
- Cada empresa deve enxergar apenas seus dados.
- Usar RLS em todas as tabelas de negocio.
- Validar tenant e permissoes no banco, especialmente em RPCs.
- Nunca expor service_role key no app Flutter.
- Usar apenas anon key no frontend.
- Storage privado para anexos/evidencias.
- Auditoria para eventos relevantes.
- Criar rollbacks para todas as migrations.
- Criar roteiros SQL de isolamento por modulo.

Perfis iniciais:
- tenant_admin
- manager
- technician

Modulos do MVP:
1. Autenticacao e criacao de empresa.
2. Clientes, contatos, enderecos e ativos/equipamentos.
3. Chamados com categorias, prioridades, status, anexos, notas e atribuicoes.
4. Agenda mensal com tecnicos, visitas e evidencias.
5. Orcamentos com itens, calculo server-side em centavos, PDF e link publico de aprovacao/rejeicao.
6. Ordens de servico com conversao de orcamento aprovado, status de execucao, horas, materiais, despesas, evidencias e aceite com assinatura.
7. Financeiro minimo com recebiveis, baixa manual e recibo em PDF.
8. Dashboard minimo com resumo financeiro.
9. Scripts de build, smoke test, release check, preflight de seguranca e manifesto SHA-256.
10. Relatorios basicos com indicadores operacionais e financeiros usando dados existentes, RLS, filtro por periodo, busca nos rankings, filtro de situacao, copia do resumo gerencial, exportacao CSV, grafico mensal, ranking de clientes, ranking de tipos de servico, ranking de tecnicos e popups de detalhe nos rankings com movimentos recentes.
11. Pesquisa de satisfacao simples vinculada a OS concluida, com nota de 1 a 5, respondente opcional e comentario opcional.

Migrations esperadas, em ordem:
- 0001_foundation.sql
- 0002_customers.sql
- 0003_service_requests.sql
- 0004_scheduling.sql
- 0005_quotations.sql
- 0006_quotation_public_flow.sql
- 0007_quotation_public_revoke.sql
- 0008_work_orders.sql
- 0009_work_order_execution.sql
- 0010_work_order_acceptance.sql
- 0011_work_order_expenses.sql
- 0012_work_order_evidence_storage.sql
- 0013_financials_minimum.sql
- 0014_customer_satisfaction.sql

Buckets esperados:
- service-request-attachments
- work-order-evidence

Scripts esperados:
- scripts/build_staging.sh
- scripts/smoke_web.sh
- scripts/release_check.sh
- scripts/write_release_manifest.sh
- scripts/security_preflight.sh

Documentacao obrigatoria:
- README.md
- docs/DOCS_INDEX.md
- docs/SYSTEM_MANUAL.md
- docs/SQL_MANUAL.md
- docs/RECREATE_PROMPT.md
- docs/PROJECT_STATE.md
- docs/DEPLOY_STAGING.md
- docs/MVP_RELEASE_CHECK.md
- docs/RELEASE_NOTES_MVP.md
- docs/CHANGELOG.md
- docs/SECURITY.md
- docs/THREAT_MODEL.md
- docs/DATA_MODEL.md
- docs/DECISIONS.md
- test/reports/reports_screen_test.dart

Fluxo de validacao:
- flutter pub get
- flutter pub run build_runner build
- flutter analyze
- testes Flutter criticos
- flutter build web com dart-define-from-file
- smoke test local
- preflight de seguranca
- validacao SQL de isolamento com usuarios reais
- smoke test na URL publicada

Criterios de aceite:
- Usuario consegue logar com e-mail e senha.
- Se ja possuir empresa, nao fica preso em /criar-empresa; qualquer acesso a essa rota com empresa ativa redireciona para /dashboard.
- Usuario cria cliente, chamado, agendamento e orcamento por popup; no cliente, contato principal e endereco padrao sao gravados no primeiro cadastro.
- No popup de novo chamado, o campo Cliente deve ser pesquisavel dentro da propria lista por nome, CPF, CNPJ ou telefone, mostrando documento/telefone nas sugestoes.
- Agenda permite trocar meses para esquerda e direita.
- Clique em uma data abre popup de agendamento.
- Orcamento gera PDF e link publico.
- Link publico permite aprovacao/rejeicao sem login.
- Orcamento aprovado vira OS.
- Chamados, orcamentos e OS permitem anexar fotos no cadastro/popup para identificacao, catalogo e historico de clientes, equipamentos e servicos.
- Cards de chamados, orcamentos e OS possuem botao `Rota`, abrindo Google Maps, Waze, Apple Maps ou copia do endereco para profissionais em celular/tablet.
- Listas de chamados, orcamentos e OS exibem `Roteiro sugerido`, ordenando por criticidade/prioridade, horario e distancia aproximada quando houver latitude/longitude. As coordenadas sao preenchidas no cadastro/edicao de endereco do cliente por um bloco neomorfico `Localizacao para rotas`.
- OS permite horas, materiais, despesas, fotos/evidencias e aceite.
- Financeiro permite gerar cobranca, registrar pagamento e gerar recibo.
- OS concluida permite registrar satisfacao do cliente com nota de 1 a 5.
- Relatorios mostra clientes, chamados, agenda, OS, satisfacao media, contagem de avaliacoes, avaliacoes criticas, orcamentos, financeiro e tecnicos em uma tela gerencial com filtro de periodo, busca nos rankings, filtro de situacao, acao de copiar resumo, exportacao CSV, grafico mensal, rankings operacionais e popups de detalhe ao clicar nos rankings, incluindo movimentos recentes do periodo.
- RLS impede vazamento entre empresas.
- Build web nao contem segredos.
- Pacote staging passa no smoke test.

Ao reconstruir, leia primeiro a documentacao existente nesta ordem:
1. README.md
2. docs/DOCS_INDEX.md
3. docs/PROJECT_STATE.md
4. docs/SYSTEM_MANUAL.md
5. docs/SQL_MANUAL.md
6. docs/DELIVERY_1.md
7. docs/DATA_MODEL.md
8. docs/DECISIONS.md
9. docs/DEPLOY_STAGING.md

Depois implemente por fases pequenas, validando cada fase antes de seguir para a proxima. Sempre atualize docs/PROJECT_STATE.md, docs/SYSTEM_MANUAL.md, docs/SQL_MANUAL.md, docs/RECREATE_PROMPT.md e docs/CHANGELOG.md quando houver mudanca relevante.
```

## Observacoes para uso

Se o repositorio antigo ainda existir, use os arquivos reais como fonte principal. Este prompt serve para orientar uma reconstrucao fiel, mas os SQLs em `supabase/migrations/` e os documentos do projeto devem prevalecer sobre qualquer memoria externa.

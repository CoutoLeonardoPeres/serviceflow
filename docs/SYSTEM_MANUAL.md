# ServiceFlow — Manual do Sistema

Ultima atualizacao: 2026-07-23

## Objetivo

O ServiceFlow e um SaaS para empresas de servicos tecnicos em campo. Ele atende prestadores genericos como eletricistas, encanadores, tecnicos de refrigeracao, manutencao predial, assistencias e pequenas operacoes de servico.

O MVP cobre o fluxo principal:

1. Login por e-mail e senha.
2. Criacao da empresa.
3. Cadastro de clientes.
4. Abertura de chamados.
5. Agenda mensal com popup de agendamento.
6. Orcamentos com PDF e link publico de aprovacao.
7. Ordens de servico com execucao, horas, materiais, despesas, evidencias e aceite.
8. Financeiro minimo com recebiveis, baixa manual e recibos.
9. Pacote de publicacao web para staging.
10. Relatorios basicos para acompanhamento gerencial.
11. Onboarding comercial do plano com opcao de abrir checkout externo configuravel.
12. Tela de assinatura com portal de cobranca configuravel.
13. Registro de sessao de checkout e retorno comercial antes da confirmacao final do pagamento.
14. Confirmacao manual do checkout em Configuracoes para ativar o plano antes do webhook do gateway.
15. Registro e simulacao de webhooks de cobranca para validar o fluxo automatico antes da integracao com o provedor real.
16. Pesquisa de satisfacao simples apos conclusao da OS.

## Stack atual

- Aplicacao: Flutter Web.
- Estado e injecao: Riverpod.
- Rotas: GoRouter.
- Backend: Supabase Auth, Database, RPCs, RLS e Storage.
- Autenticacao: e-mail e senha.
- Design: neomorfismo claro, moderno e futurista, com popups para cadastros e acoes principais.
- Hospedagem prevista: build web estatico publicado em Apache/Hostinger.

## Perfis de acesso

Os perfis iniciais sao:

- `tenant_admin`: administra a empresa, usuarios, cadastros e configuracoes.
- `manager`: gerencia operacao, clientes, chamados, agenda, orcamentos, OS e financeiro.
- `technician`: executa servicos, agenda, OS, evidencias, horas, materiais e aceite.

O banco tambem usa permissoes granulares por modulo. A interface pode continuar simples, mas a seguranca deve ser decidida no servidor.

## Identidade visual

Todas as telas devem seguir a direcao visual ja aprovada:

- Fundo claro acinzentado.
- Cartoes e superficies com relevo neomorfico.
- Sombras suaves externas e internas.
- Bordas arredondadas consistentes.
- Acoes primarias em roxo/indigo.
- Formularios em popup sempre que forem cadastros ou criacoes rapidas.
- Formularios devem usar campos lado a lado quando houver largura, em secoes neomorficas com relevo. Campos longos, como descricao e observacoes, podem ocupar largura maior quando necessario.
- Icones em botoes e menus.
- Evitar telas brancas durante carregamento; usar splash/loading neomorfico.

Telas de cadastro que devem abrir em popup:

- Novo cliente.
- Novo chamado.
- Novo agendamento.
- Novo orcamento.
- Nova OS manual.
- Baixa manual financeira.
- Registro de horas.
- Material aplicado.
- Despesa.
- Evidencia.
- Aceite do cliente.

## Fluxo de acesso

1. Usuario entra em `/login`.
2. Faz login com e-mail e senha.
3. Sistema carrega sessao do Supabase.
4. Sistema busca empresa/membership ativo.
5. Se nao houver empresa, vai para `/criar-empresa`.
6. Se houver empresa ativa, vai para o dashboard.

Ponto importante: se o usuario ja criou a empresa, ele nao pode ficar preso em `/criar-empresa`. O cache de empresa/membership deve ser invalidado apos login, criacao da empresa e logout; alem disso, qualquer acesso a `/criar-empresa` com empresa ativa deve redirecionar para `/dashboard`.

## Modulos

### Dashboard

Mostra indicadores iniciais da operacao e financeiro:

- Saldo em aberto.
- Saldo vencido.
- Total de recebiveis.
- Atalho para Financeiro.

### Clientes

Permite listar, filtrar, criar e editar clientes.

A lista e a tela de detalhe do cliente devem exibir um botao visivel `Editar cliente`, abrindo o formulario em popup para alterar dados cadastrais sem procurar a acao em menus secundarios.

Dados atuais:

- Tipo de cliente: pessoa fisica ou juridica.
- Documento.
- Nome.
- Status ativo/inativo.
- Contatos.
- Enderecos.
- Ativos/equipamentos do cliente.

No cadastro de novo cliente, o popup deve incluir:

- Pessoa de contato principal, preenchida inicialmente com o nome do cliente, mas editavel quando o contato for outra pessoa.
- Telefone e e-mail do contato principal.
- Endereco padrao obrigatorio, iniciando pelo CEP.
- Busca automatica de CEP para preencher rua, bairro, cidade e UF quando o CEP existir na base publica.
- Botao `Localizar` no bloco de endereco para preencher latitude/longitude e melhorar a roteirizacao por distancia.

Na tela de detalhe do cliente, novos enderecos e enderecos existentes tambem possuem o botao `Localizar`/`Atualizar`. Quando as coordenadas ja existem, o sistema exibe a latitude/longitude salvas no proprio bloco.

### Chamados

Permite registrar uma demanda de servico.

Dados principais:

- Cliente.
- Contato.
- Endereco.
- Categoria.
- Prioridade.
- Descricao.
- Status.
- Anexos.
- Notas.
- Atribuicoes.

No popup de novo chamado, o campo Cliente deve permitir busca na propria lista por nome, CPF, CNPJ ou telefone, exibindo documento/telefone como apoio para diferenciar clientes parecidos.

### Agenda

A agenda deve ser visualmente parecida com a referencia enviada pelo usuario:

- Calendario mensal.
- Setas para navegar mes anterior e proximo mes.
- Dias organizados de segunda a domingo.
- Cores de estado: livre, ocupado e fechado.
- Marcadores por periodo: manha, tarde e noite.
- Clique no dia abre popup de agendamento.
- Agenda deve manter o estilo neomorfico com relevos nas celulas.

### Orcamentos

Fluxo:

1. Criar orcamento em popup.
2. Adicionar itens.
3. Banco calcula totais em centavos.
4. Detalhe permite gerar PDF.
5. Detalhe permite gerar link publico.
6. Cliente acessa link publico e aprova, rejeita ou solicita alteracao.
7. Link pode ser revogado.

### Ordens de Servico

Uma OS pode ser criada manualmente ou convertida a partir de um orcamento aprovado.

Fluxo principal:

1. Gerar OS.
2. Iniciar execucao.
3. Registrar horas.
4. Adicionar materiais.
5. Registrar despesas.
6. Anexar fotos/evidencias no Storage privado.
7. Registrar aceite com assinatura desenhada.
8. Concluir OS.
9. Gerar cobranca.
10. Registrar satisfacao do cliente com nota de 1 a 5 e comentario opcional.

A satisfacao so deve ser registrada para OS concluida. O detalhe da OS mostra o botao `Registrar satisfação` e, depois do salvamento, exibe a nota registrada.

A tela de Relatorios consolida a satisfacao no periodo selecionado com nota media, quantidade de avaliacoes e quantidade de avaliacoes criticas. O resumo copiado e o CSV exportado tambem incluem esses indicadores.

Chamados possuem campo de fotos no cadastro/popup. Orcamentos e OS possuem campo de anexos no cadastro/popup, aceitando fotos e documentos operacionais. Esses arquivos ajudam a identificar cliente, equipamento, local e servico, e ficam salvos como catalogo/historico privado da empresa. Chamados usam o bucket `service-request-attachments`, orcamentos usam `quotation-attachments` e OS usa `work-order-evidence`.

### Rotas de campo

Os cards de Chamados, Orcamentos e OS exibem botao `Rota` quando houver endereco do atendimento ou endereco principal do cliente. O botao abre opcoes para Google Maps, Waze, Apple Maps e copia do endereco.

As listas de Chamados, Orcamentos e OS exibem um painel `Roteiro sugerido`, ordenando atendimentos por criticidade/prioridade, horario marcado ou validade, e distancia aproximada quando o endereco possuir latitude/longitude. As coordenadas podem ser preenchidas no cadastro/edicao do endereco do cliente pelo botao `Localizar`. Se nao houver coordenadas, a rota ainda usa o endereco textual nos apps de mapa, mas a distancia fica indisponivel.

### Financeiro

MVP financeiro minimo:

- Recebiveis criados a partir de OS.
- Baixa manual de pagamento.
- Controle de saldo em aberto.
- Recibo em PDF.
- Resumo no dashboard.

Nao inclui ainda:

- Integracao automatica Pix/boleto/cartao.
- Conciliacao bancaria.
- Nota fiscal.
- Relatorios financeiros avancados.

### Relatorios

A tela de Relatorios consolida uma visao gerencial simples usando os dados ja existentes no sistema.

Indicadores atuais:

- Clientes ativos e inativos.
- Chamados abertos.
- Agendamentos ainda nao finalizados.
- OS abertas e concluidas.
- Pipeline de orcamentos em negociacao e aprovados.
- Saldo financeiro em aberto.
- Saldo vencido.
- Valor recebido por baixas registradas.

Controles atuais:

- Filtro rapido por `30 dias`, `Mês atual`, `Ano atual` e `Tudo`.
- Busca nos rankings por cliente, tecnico, chamado, tipo ou status.
- Filtro de situacao para refinar rankings por `Todos`, `Em aberto`, `Fechados`, `Financeiro` e `Agenda`.
- Botao para copiar o resumo gerencial para a area de transferencia.
- Botao para exportar o resumo filtrado em CSV.
- Grafico de tendencia mensal com chamados, OS concluidas e valores recebidos.
- Ranking `Clientes em destaque` por movimento financeiro e atividade no periodo.
- Ranking `Tipos de servico em alta` por volume de chamados, abertos e fechados.
- Ranking `Tecnicos em campo` por agendamentos, apontamentos e horas trabalhadas.
- Clique em um item dos rankings abre um popup neomorfico com o resumo daquele cliente, tipo de servico ou tecnico.
- Cada popup mostra metricas principais e uma lista de movimentos recentes do periodo, como chamados, OS, recebiveis, agendas e apontamentos de horas.

Nesta primeira versao nao ha nova tabela SQL. Os dados sao lidos das tabelas existentes e continuam protegidos pelo RLS do Supabase.

Evolucoes previstas:

- Links dos movimentos para as telas de origem e exportacao considerando os filtros de tela.

## Rodar localmente

1. Copiar `dart_defines/dev.example.json` para `dart_defines/dev.json`.
2. Preencher URL e chave publica anon do Supabase.
3. Instalar dependencias Flutter.
4. Gerar os arquivos Freezed.
5. Fazer build web.
6. Servir `build/web` em uma porta local.

Comandos principais ficam no `README.md`.

## Build e publicacao

Para gerar pacote de staging:

```bash
./scripts/build_staging.sh
```

Para validar antes de publicar:

```bash
./scripts/release_check.sh dart_defines/dev.json 8091
./scripts/security_preflight.sh dist/serviceflow-staging.zip --remote
```

Guia completo: `docs/DEPLOY_STAGING.md`.

## Validacao manual recomendada

Antes de considerar uma fase pronta:

1. Entrar com e-mail e senha.
2. Confirmar que o usuario sai corretamente da tela de login/criacao de empresa.
3. Criar cliente em popup com contato principal e endereco padrao.
4. Criar chamado em popup.
5. Agendar visita clicando em uma data da agenda.
6. Criar orcamento em popup.
7. Gerar PDF do orcamento.
8. Gerar link publico e aprovar.
9. Converter orcamento aprovado em OS.
10. Registrar horas, material, despesa, fotos/evidencias e aceite.
11. Gerar cobranca.
12. Registrar pagamento.
13. Gerar recibo.
14. Registrar satisfacao na OS concluida.
15. Conferir se os dados de uma empresa nao aparecem em outra.
16. Conferir a tela de Relatorios e validar se os indicadores, incluindo satisfacao media e avaliacoes criticas, batem com os registros criados.

## Como manter este manual

Atualize este documento sempre que:

- Uma tela nova for criada.
- Uma tela deixar de ser popup ou passar a ser popup.
- Um fluxo do usuario mudar.
- Uma permissao ou perfil mudar.
- Um modulo novo entrar no MVP.
- Uma etapa de deploy ou validacao mudar.

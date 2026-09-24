# Migração visual do ServiceFlow

Data: 24 de setembro de 2026

## Objetivo

Reformular toda a interface do ServiceFlow com o sistema visual do `App_Cli_Manager`. A migração preservará regras de negócio, dados, rotas, permissões e fluxos atuais. O ServiceFlow manterá sua cor principal azul.

## Fonte de verdade

Os arquivos abaixo do `App_Cli_Manager` definem o padrão visual:

- `apps/mobile/lib/core/design/neu_tokens.dart`
- `apps/mobile/lib/core/design/neu_widgets.dart`
- `apps/mobile/lib/core/theme.dart`
- telas de dashboard, agenda, formulários e módulos em `apps/mobile/lib/features/clinic`

Novos componentes do ServiceFlow devem usar o mesmo sistema. Valores visuais não devem ser duplicados em telas.

## Identidade visual

### Cores

| Papel | Cor |
| --- | --- |
| Fundo e superfícies | `#E0E5EC` |
| Texto principal | `#3D4852` |
| Texto secundário | `#6B7280` |
| Placeholder | `#A0AEC0` |
| Principal do ServiceFlow | `#6F68F8` |
| Principal clara | `#8D87FA` |
| Sucesso | `#38B2AC` |
| Sombra escura | `rgba(163, 177, 198, 0.65)` |
| Sombra clara | `rgba(255, 255, 255, 0.55)` |

A cor rosa `#9C4D6D` da referência não será usada. O azul `#6F68F8` assumirá o mesmo papel em botões principais, seleção, foco, ícones ativos e indicadores.

### Tipografia

- Plus Jakarta Sans: títulos, cabeçalhos e números em destaque.
- DM Sans: textos, campos, botões, listas e informações operacionais.
- Pesos 700 e 800 estabelecem hierarquia; textos corridos usam 400 a 600.
- A interface não usará espaçamento negativo entre letras.
- Textos devem responder à escala do sistema sem sobreposição ou corte.

### Forma e profundidade

- Cards e grandes painéis: raio de `32px`.
- Campos, botões e controles: raio de `16px`.
- Elementos internos e poços de ícone: raio de `12px`.
- Chips e seletores compactos: formato de cápsula quando adequado.
- Superfícies elevadas usam sombras opostas clara e escura.
- Campos e estados pressionados usam profundidade interna.
- Contornos aparecem apenas para foco, erro, seleção ou separação necessária.

### Movimento

- Transições de estado usam 300 ms e curva `easeOut`.
- Hover eleva controles acionáveis em até 2px.
- Pressionar reduz a profundidade sem deslocar o layout.
- Animações servem apenas para foco, abertura, seleção e confirmação.

## Componentes globais

O ServiceFlow terá uma única biblioteca visual para:

- superfície elevada, superfície interna e card acionável;
- poço de ícone;
- botão principal, secundário, de texto e de ícone;
- campos de texto, busca, seleção, data e hora;
- chips, filtros, estados e controles segmentados;
- cabeçalho de página e barra de ações;
- listas, tabelas, cards de dados e estados vazios;
- carregamento, erro e confirmação;
- modal, popup, diálogo de formulário e painel lateral;
- navegação lateral no desktop e navegação compacta no mobile.

Todos os componentes devem incluir hover, foco por teclado, pressionado, desabilitado, carregamento e mensagem de erro quando aplicável.

## Estrutura das telas

### Desktop

```text
+----------------------+-----------------------------------------+
| Marca                | Título e ações                          |
| Navegação            +-----------------------------------------+
|                      | Filtros / resumo                        |
|                      +-----------------------------------------+
|                      | Conteúdo operacional                    |
| Usuário              |                                         |
+----------------------+-----------------------------------------+
```

- A navegação permanece lateral, rolável e recolhível em larguras intermediárias.
- O conteúdo usa largura disponível e grades responsivas.
- A ação principal fica no cabeçalho ou no canto inferior da área de trabalho, conforme o fluxo.

### Mobile

```text
+----------------------+
| Título e ações       |
+----------------------+
| Conteúdo rolável     |
|                      |
+----------------------+
| Navegação compacta   |
+----------------------+
```

- Formulários passam para uma coluna.
- Tabelas viram listas ou cards operacionais.
- Modais ocupam quase toda a tela e preservam cantos arredondados.
- Alvos de toque têm pelo menos 44px.

## Modais e formulários

- Todos os cadastros continuarão em popup quando esse for o fluxo atual.
- O contêiner externo terá cantos arredondados e não deixará aparecer fundo quadrado.
- O cabeçalho terá título, ação de fechar e separação visual discreta.
- O conteúdo será rolável, com rodapé de ações estável quando necessário.
- Campos relacionados ficarão lado a lado em telas largas e empilhados no mobile.
- A ação principal ocupará destaque visual; cancelar e fechar permanecerão disponíveis.
- Validação aparecerá junto ao campo, sem depender apenas de cor.

## Migração por etapas

### 1. Fundação visual

- Adicionar as fontes da referência.
- Substituir paleta, tipografia, raios, espaçamentos e sombras globais.
- Criar os componentes equivalentes a `NeuSurface`, `NeuCard`, `NeuButton`, `NeuFieldShell`, `NeuIconWell` e `NeuPage`.
- Atualizar temas Material e estados de interação.

### 2. Estrutura e navegação

- Migrar fundo, shell responsivo, barra lateral, navegação mobile, cabeçalhos e menus.
- Garantir rolagem sem overflow em todos os tamanhos.

### 3. Formulários e modais

- Migrar todos os diálogos de cadastro e edição.
- Padronizar campos, seletores, máscaras, ações e mensagens.
- Corrigir qualquer diálogo com fundo ou canto quadrado.

### 4. Telas operacionais

- Dashboard e onboarding.
- Clientes, profissionais e configurações.
- Chamados, agenda, orçamentos e ordens de serviço.
- Estoque, compras, fornecedores e materiais.
- Financeiro, pagamentos, fiscal, relatórios e módulos comerciais.

### 5. Estados e acabamento

- Padronizar carregamento, vazio, erro, confirmação e permissões.
- Remover cores, sombras, fontes e raios locais que escapem do tema.
- Revisar responsividade, teclado, foco, contraste e escala de texto.

## Compatibilidade funcional

A migração não altera:

- Supabase, tabelas, políticas ou migrações;
- autenticação, onboarding e regras de plano;
- permissões e isolamento entre empresas;
- modelos, repositórios e providers;
- rotas públicas e internas;
- regras de agenda, financeiro, estoque e execução de serviços.

Mudanças funcionais identificadas durante a migração serão tratadas separadamente.

## Testes e validação

- Executar análise estática e testes existentes após cada grupo de telas.
- Criar testes de widgets para componentes globais e modais.
- Validar desktop, tablet e mobile.
- Comparar capturas do ServiceFlow com telas equivalentes do `App_Cli_Manager`.
- Verificar foco visível, navegação por teclado, alvos de toque e contraste.
- Confirmar que nenhum fluxo deixa de salvar, carregar ou navegar.

## Critérios de aceite

1. Todas as telas usam a paleta, tipografia, sombras, raios e espaçamentos definidos aqui.
2. Botões, campos, cards, filtros e modais têm os mesmos estados e proporções da referência.
3. Nenhum popup apresenta canto externo quadrado.
4. Desktop, tablet e mobile funcionam sem overflow ou conteúdo inacessível.
5. A cor principal permanece azul `#6F68F8`.
6. O comportamento funcional existente permanece intacto.
7. A análise estática, os testes automatizados e a compilação web passam.

## Decisões finais

- Abordagem escolhida: migração completa e progressiva do sistema visual.
- Referência: versão atual da pasta `/Users/leonardoperescouto/Documents/App_Cli_Manager`.
- Identidade preservada: azul do ServiceFlow.
- Elemento característico: profundidade neumórfica consistente em superfícies e controles, com interação clara e sem decoração gratuita.

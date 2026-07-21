# ServiceFlow — Visão do Produto

> Nome provisório. Nome comercial será configurável (white-label leve por tenant: nome, logotipo, cores).

## 1. Visão

SaaS multiempresa brasileiro para gestão do ciclo completo de atendimento e prestação de serviços técnicos em campo (Field Service Management): do primeiro contato do cliente até pagamento, repasse e pesquisa de satisfação. Foco inicial em pequenas empresas e autônomos de serviços técnicos (elétrica, hidráulica, refrigeração, informática, instalação, manutenção predial/industrial, facilities), com escala futura para redes de assistência e parceiros terceirizados.

**Proposta de valor central:** uma pequena empresa consegue, no mesmo dia da adesão, cadastrar um cliente, abrir um chamado, orçar, aprovar por link, executar a OS no celular e receber — sem planilhas nem WhatsApp desorganizado.

**Diferenciais:** fluxo comercial→operacional→financeiro integrado com rastreabilidade ponta a ponta; aprovação de orçamento por link seguro sem exigir conta do cliente; app do técnico otimizado para celular e rede instável; multiempresa com isolamento forte desde a primeira migration.

## 2. Personas

| Persona | Papel típico | Objetivo | Dor principal |
|---|---|---|---|
| **Dono/gestor** (Carlos, eletricista com 4 funcionários) | tenant_owner | Visão do negócio, orçamentos, cobrança | Perde orçamentos no WhatsApp, não sabe margem real |
| **Analista/atendente** (Juliana) | analyst/dispatcher | Registrar chamados, agendar, acompanhar | Retrabalho, informação espalhada, cliente sem retorno |
| **Técnico de campo** (Marcos) | technician | Ver agenda, executar OS, registrar evidências | Papel, foto solta no celular, esquecimento de material usado |
| **Financeiro** (Ana) | financial_operator | Receber, conciliar, cobrar inadimplentes | Não sabe o que foi pago; conciliação manual |
| **Parceiro terceirizado** (fase 5) | partner | Receber OS, executar, receber repasse | Falta de transparência no repasse |
| **Cliente final** (Sr. Roberto / síndica de condomínio) | customer_portal_user / link público | Aprovar orçamento, acompanhar, pagar | Não quer criar conta; quer clareza de preço e prazo |
| **Admin da plataforma** | platform_admin | Operar o SaaS, suporte auditado | Suporte sem violar isolamento |

## 3. Mapa da jornada (ponta a ponta)

```
Contato (tel/WhatsApp/e-mail/form)
 → Identificação/cadastro do cliente (analista ou link seguro de auto-cadastro)
 → Registro do chamado (solicitante, problema, categoria, prioridade, endereço, disponibilidade, anexos, equipamentos)
 → Triagem → [Visita técnica agendada → diagnóstico] (opcional)
 → Orçamento (serviços + horas + materiais + custos adicionais + impostos + margem + desconto)
 → Envio por PDF/link seguro → cliente aprova / rejeita / pede alteração
 → [Adiantamento, se exigido]
 → OS gerada (conversão idempotente) → agendamento → designação (técnico/parceiro)
 → Execução: check-in, apontamento de horas, pausas, materiais, evidências, despesas, pendências
 → Conclusão → aceite assinado pelo cliente
 → Recibo/documento fiscal → pagamento → contas a receber + baixa
 → Baixa de estoque, apropriação de custos/comissões, repasse a parceiros
 → Pesquisa de satisfação → indicadores
```

## 4. Escopo funcional completo (produto-alvo)

32 módulos, conforme ARCHITECTURE.md §2: identidade/acesso, tenant, assinaturas, usuários/equipes, clientes, contatos, endereços, chamados, agenda, visitas, orçamentos, OS, horas, materiais, estoque, compras, fornecedores, financeiro, pagamentos, fiscal, parceiros, comissões, contratos, preventivas, frota, despesas, comunicação, satisfação, relatórios, indicadores, auditoria, administração SaaS.

## 5. Escopo do MVP (Fases 0–1)

- Autenticação, tenant, membership, RBAC, RLS, auditoria básica.
- Clientes (PF/PJ/condomínio), contatos, endereços.
- Catálogo básico de serviços e materiais; tabela de homem-hora.
- Chamados: abertura, listagem/filtros, detalhe, categorias, prioridades, anexos, atribuição.
- Agenda básica e visita técnica.
- Orçamento: itens (serviço, hora, material, deslocamento, custos adicionais), desconto, impostos informados, versão, PDF, link público seguro, aprovação/rejeição/solicitação de alteração.
- Conversão idempotente para OS; execução (status, check-in/out, horas, materiais usados, fotos, observações, despesas); aceite com assinatura.
- Recebimento manual (dinheiro, Pix manual, transferência, maquininha registrada manualmente), contas a receber básicas, recibo simples.
- Dashboard operacional mínimo. Deploy staging (Hostinger + Supabase).

## 6. Fora do MVP

Estoque com saldo/movimentos/reservas (F3), compras/fornecedores (F3), financeiro completo — contas a pagar, fluxo de caixa, conciliação, DRE (F4), parceiros e repasses (F5), contratos/SLA/preventivas (F6), frota (F7), integrações: API oficial WhatsApp, gateway de pagamento, Pix automático, provedor fiscal, mapas (F8), BI avançado e automações (F9), múltiplos tenants por usuário na UI (modelo de dados já suporta), modo offline do técnico (arquitetura não deve impedi-lo), MFA obrigatório (preparado para admins), emissão fiscal (apenas abstração + registro de "solicitação de emissão").

## 7. Riscos de negócio

| Risco | Impacto | Mitigação |
|---|---|---|
| MVP demorar e perder janela de validação | Alto | Fases estritas; nada avançado antes da F1 |
| Complexidade fiscal brasileira travar adoção | Alto | Sem motor fiscal no MVP; recibo simples + abstração FiscalProvider |
| Cliente final não adotar link (preferir WhatsApp informal) | Médio | Link sem conta, mobile-first, registro manual de comunicação |
| Concorrência estabelecida (Field Control, Auvo, Produttivo) | Médio | Foco em simplicidade + preço para micro/pequena empresa |
| Churn por curva de aprendizado | Médio | Onboarding guiado, seeds de categorias/serviços comuns por segmento |
| Dependência do Supabase | Médio | Monólito modular, SQL padrão, camada de abstração de providers |
| Inadimplência do assinante do SaaS | Baixo | Assinaturas/planos na F2+; bloqueio suave por status do tenant |

## 8. Premissas registradas (não bloqueantes)

1. Idioma único pt-BR no MVP; i18n preparada.
2. Timezone padrão America/Sao_Paulo por tenant, configurável; armazenamento UTC.
3. Moeda única BRL no MVP; NUMERIC(14,2) para valores, NUMERIC(14,4) para custos unitários.
4. Impostos no MVP: informados manualmente por orçamento ou via tax profile simples (percentual). Sem cálculo tributário automático.
5. Assinatura do aceite: assinatura desenhada na tela (imagem) + metadados (data, quem, IP proporcional). Sem certificado digital no MVP.
6. Plano/assinatura do SaaS: no MVP todo tenant é criado ativo sem cobrança (billing na F2+).
7. Auto-cadastro de cliente por link: presente no MVP em forma simples (completar dados cadastrais).

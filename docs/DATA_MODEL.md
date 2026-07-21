# ServiceFlow — Modelo de Dados (MVP)

Convenções globais: PK `id uuid default gen_random_uuid()`; toda tabela de tenant tem `tenant_id uuid not null references tenants`, `created_at/updated_at timestamptz` (UTC, trigger), `created_by/updated_by uuid` quando aplicável; moeda `numeric(14,2)` (custo unitário `numeric(14,4)`); quantidades `numeric(12,3)`; unicidade sempre composta com `tenant_id`; RLS habilitado em todas; soft delete só onde indicado; FKs e checks explícitos; índice em todo `tenant_id` + colunas de filtro.

## 1. Identidade e tenancy (F0 — migration 0001)

- **tenants**: name, slug (unique), status (`active|suspended|closed`), timezone default 'America/Sao_Paulo'.
- **tenant_settings**: tenant_id (unique), branding (nome exibido, logo_path, cores), quote_validity_days, moeda, chaves de configuração não sensíveis (jsonb validado).
- **tenant_sequences**: tenant_id, kind (`quote|work_order|receipt|service_request`), next_value. Incremento via função com lock (`FOR UPDATE`).
- **profiles**: id = auth.users.id, full_name, phone, avatar_path.
- **tenant_memberships**: tenant_id, user_id, role_id, status (`invited|active|suspended|removed`), unique(tenant_id, user_id).
- **roles**: seed global + por tenant no futuro; key (`tenant_owner`, `tenant_admin`, `manager`, `analyst`, `dispatcher`, `technician`, `warehouse_operator`, `financial_operator`, `partner`, `customer_portal_user`, `viewer`); `platform_admin` fora de membership (flag em tabela dedicada `platform_admins`).
- **permissions** / **role_permissions**: chaves `recurso.ação` (ex.: `quotes.approve_discount`).
- **user_invitations**: tenant_id, email, role_id, token_hash, expires_at, accepted_at, revoked_at.
- **audit_logs**: tenant_id nullable (ações de plataforma), actor_id, action, entity, entity_id, before/after (jsonb, campos sensíveis excluídos), origin, request_id, ip proporcional, created_at. Particionável no futuro; INSERT-only (sem UPDATE/DELETE via policy).

## 2. Clientes (F1)

- **customers**: type (`person|company|condominium|public_entity`), name, trade_name, document (CPF/CNPJ validado, unique parcial por tenant quando não nulo), email, phone, notes, is_active, payer_customer_id (nullable, para solicitante≠pagador).
- **customer_contacts**: customer_id, name, role, phone, whatsapp, email, is_primary.
- **customer_addresses**: customer_id, label, cep, street, number, complement, district, city, state (UF check), reference, lat/lng nullable, is_default.
- **customer_assets** (equipamentos): customer_id, address_id nullable, name, brand, model, serial_number, notes. (MVP simples.)
- **customer_portal_access**: customer_id, contact_id, token_hash, scope, expires_at, revoked_at, last_access_at. (auto-cadastro/portal leve.)
- customer_notes / customer_documents: F2.

## 3. Atendimento (F1)

- **service_categories**: name, seed por segmento; **service_priorities**: name, level, sla_hours nullable.
- **service_requests** (chamados): number (por tenant), customer_id, requester_contact_id, address_id, category_id, priority_id, title, description, availability_notes, channel (`phone|whatsapp|email|form|in_person`), status (máquina §7), assigned_to nullable.
- **service_request_status_history**: request_id, from_status, to_status, actor_id, reason, created_at.
- **service_request_attachments**: request_id, storage_path, mime_type, size, checksum, uploaded_by. (mime allowlist; nome gerado pelo sistema.)
- **service_request_notes**, **service_request_assignments** (histórico de atribuição).

## 4. Agenda e visita (F1)

- **appointments**: tenant_id, kind (`visit|work_order`), reference_id, customer_id, address_id, scheduled_start/end, status (`scheduled|confirmed|done|cancelled|no_show`), notes.
- **appointment_assignments**: appointment_id, technician_user_id. Conflito: constraint por exclusão (tstzrange + EXCLUDE USING gist por técnico) ou validação em função transacional — decisão ADR-010.
- **technical_visits**: request_id, appointment_id, diagnosis, executed_at, technician_id.
- **visit_evidence**: visit_id, storage_path, kind (`photo|video|document`), checksum.
- technician_availability, visit_checkins, visit_expenses, travel_records: F2+ (check-in no MVP fica na OS).

## 5. Orçamento (F1)

- **quotations**: number por tenant, customer_id, request_id nullable, current_version_id, status (máquina §7), valid_until, requires_advance bool, advance_type (`percent|fixed`), advance_value, notes/terms/warranty_terms.
- **quotation_versions**: quotation_id, version_number, snapshot imutável dos itens/totais no momento do envio, subtotal_services, subtotal_labor, subtotal_materials, subtotal_additional_costs, discount_type/value, tax_total, total, internal_cost_total, gross_margin, created_by. Unique(quotation_id, version_number).
- **quotation_items**: version_id, kind (`service|labor_hour|material|equipment|travel|per_diem|meal|parking|toll|transport|lodging|tax|fee|discount|other`), description, catalog_ref nullable, quantity, unit_price, unit_cost, total. Totais recalculados server-side (trigger/função).
- **quotation_public_links**: quotation_id, version_id, token_hash, expires_at, revoked_at, max_uses nullable, use_count, last_access_at.
- **quotation_approvals**: version_id, decision (`approved|rejected|change_requested`), decided_at, channel, approver_name, otp_used bool, ip, user_agent, comments. Unique parcial: uma aprovação `approved` por quotation.
- **quotation_status_history**. quotation_taxes/discounts detalhados: representados como itens no MVP; tabelas próprias na F4 se necessário.

## 6. Ordem de Serviço, execução e financeiro básico (F1)

- **work_orders**: number por tenant, customer_id, address_id, quotation_id nullable (unique — garante conversão idempotente), request_id nullable, status (máquina §7), scheduled info via appointments, description, totals espelhados da versão aprovada.
- **work_order_items**: espelho dos itens aprovados + ajustes autorizados.
- **work_order_assignments**: work_order_id, user_id, role (`lead|support`).
- **work_order_time_entries**: work_order_id, technician_id, started_at, ended_at nullable, pauses (tabela filha `time_entry_pauses`), hour_type, cost_rate, sell_rate, approved_by nullable. Check: ended>started. Sobreposição por técnico bloqueada (mesma técnica do agendamento).
- **work_order_materials**: work_order_id, product_id nullable, description, quantity, unit_cost, unit_price. (Sem estoque no MVP — vira movimento na F3.)
- **work_order_expenses**: kind (`travel|toll|parking|meal|lodging|freight|other`), amount, receipt_path nullable.
- **work_order_evidence**: kind (`photo_before|photo_after|photo|video|document`), storage_path, checksum.
- **work_order_signatures** (aceite): work_order_id, signer_name, signer_document_partial, signature_image_path, signed_at, ip, user_agent, otp_used.
- **work_order_status_history**, **work_order_occurrences** (pendências).
- **receivables**: work_order_id nullable, customer_id, description, due_date, amount, status (`open|partially_paid|paid|cancelled`), balance.
- **payment_records** (recebimento manual MVP): receivable_id, method (`cash|pix_manual|transfer|card_machine|other`), amount, paid_at, reference (NSU etc.), fees, net_amount, received_by. Baixa via função transacional que atualiza receivable.balance.
- **receipts**: number por tenant, work_order_id, pdf_path, checksum, version, issued_by, issued_at.
- **generated_documents** (PDFs): entity, entity_id, version, storage_path, checksum, status, created_by. Imutável.

## 7. Catálogo (F1)

- **service_catalog**: name, description, default_price, default_cost, unit, category, is_active.
- **labor_rate_tables**: name, cost_rate, sell_rate, is_default.
- **products** (materiais): name, sku por tenant, unit_id, sell_price, cost_price, is_active. **units_of_measure** seed.
- product_categories, price_lists, tax_profiles simples (name, percent): tax_profiles entra no MVP para imposto percentual informado.

## 8. Fases futuras (resumo)

Estoque (F3): warehouses, stock_movements (única fonte de mutação de saldo), stock_balances (derivado), stock_reservations, transfers, counts, adjustments, lots/serials.
Financeiro (F4): financial_accounts, cost_centers, chart_of_accounts, payables, financial_transactions, bank_reconciliation, cash_closures.
Parceiros (F5), Contratos/Preventivas (F6), Frota (F7), Comunicação/outbox (F2/F8), Fiscal (F8: fiscal_profiles, fiscal_documents, fiscal_events, fiscal_provider_requests), Satisfação (F2+: surveys, nps_responses).

## 9. Máquinas de estado

Transições somente via função SQL `transition_<entity>(id, to_status, reason)` que valida origem→destino, permissão do papel, pré-condições; grava histórico + auditoria dentro da mesma transação. Deny by default (UPDATE direto de `status` bloqueado por trigger).

### Chamado
`draft → opened → triage → {awaiting_customer ⇄ triage} → scheduled → converted_to_quote | converted_to_work_order`; `cancelled` a partir de qualquer não-terminal; `closed` após conversão ou resolução sem OS.

### Orçamento
`draft → under_review → sent → viewed → awaiting_approval → {approved | rejected | change_requested}`; `change_requested → draft` (nova versão); `approved → partially_paid` (adiantamento) `→ converted_to_work_order`; `expired` por job/validação em acesso; `cancelled` de estados não-terminais. Envio congela a versão.

### Ordem de Serviço
`draft → awaiting_schedule → scheduled → dispatched → technician_en_route → on_site → in_progress ⇄ {paused | awaiting_material | awaiting_customer} → completed → customer_accepted → invoiced → financially_closed`; `return_required` a partir de completed/customer_accepted (gera nova OS vinculada); `cancelled` de não-terminais com motivo obrigatório.

### Pagamento
`pending → processing → {authorized → paid | failed}`; `paid → {refunded | partially_refunded | disputed}`; `partially_paid` no agregado do receivable; `cancelled` de pending/processing. (MVP manual usa subset: pending→paid/cancelled.)

Cada transição define: origem, destino, papéis, pré-condições, efeitos colaterais (ex.: approved ⇒ habilita conversão; completed ⇒ exige evidência mínima configurável), evento de auditoria, notificação, reversibilidade (apenas via transição inversa explícita, nunca UPDATE).

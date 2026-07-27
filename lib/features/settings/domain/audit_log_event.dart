/// Evento da trilha de auditoria do tenant.
class AuditLogEvent {
  const AuditLogEvent({
    required this.id,
    required this.action,
    required this.entity,
    required this.createdAt,
    this.entityId,
    this.actorId,
    this.afterData,
    this.metadata,
  });

  final String id;
  final String action;
  final String entity;
  final String? entityId;
  final String? actorId;
  final Map<String, dynamic>? afterData;
  final Map<String, dynamic>? metadata;
  final DateTime createdAt;

  /// Rótulo legível para a entidade.
  String get entityLabel => switch (entity) {
        'quotations' => 'Orçamento',
        'work_orders' => 'OS',
        'customers' => 'Cliente',
        'service_requests' => 'Chamado',
        'appointments' => 'Agendamento',
        'receivables' => 'Financeiro',
        'tenant_memberships' => 'Membros',
        'tenants' => 'Empresa',
        _ => entity,
      };

  /// Rótulo legível para a ação.
  String get actionLabel => switch (action) {
        'quotation.created' => 'Orçamento criado',
        'quotation.cancelled' => 'Orçamento cancelado',
        'quotation.new_version_created' => 'Nova versão de orçamento',
        'quotation.public_link_created' => 'Link público gerado',
        'quotation.public_link_revoked' => 'Link público revogado',
        'quotation.approved_public' => 'Orçamento aprovado (público)',
        'quotation.rejected_public' => 'Orçamento rejeitado (público)',
        'work_order.created' => 'OS criada',
        'work_order.created_from_quotation' => 'OS criada de orçamento',
        'work_order.status_changed' => 'Status de OS alterado',
        'work_order.cancelled' => 'OS cancelada',
        'work_order.return_created' => 'Retorno de OS criado',
        'work_order.time_entry_recorded' => 'Horas apontadas',
        'work_order.material_added' => 'Material registrado',
        'work_order.expense_added' => 'Despesa registrada',
        'work_order.acceptance_recorded' => 'Aceite registrado',
        'work_order.evidence_recorded' => 'Evidência registrada',
        'work_order.satisfaction.recorded' => 'Satisfação registrada',
        'customer.created' => 'Cliente criado',
        'customer.updated' => 'Cliente atualizado',
        'appointment.scheduled' => 'Agendamento criado',
        'receivable.created' => 'Cobrança gerada',
        'payment.registered' => 'Pagamento registrado',
        'member.invited' => 'Membro convidado',
        'member.activated' => 'Membro ativado',
        'member.deactivated' => 'Membro desativado',
        'member.role_changed' => 'Papel de membro alterado',
        'tenant.plan_changed' => 'Plano alterado',
        'tenant.billing_status_changed' => 'Status de cobrança alterado',
        _ => action,
      };
}

AuditLogEvent auditLogEventFromRow(Map<String, dynamic> row) => AuditLogEvent(
      id: row['id'] as String,
      action: row['action'] as String,
      entity: row['entity'] as String,
      entityId: row['entity_id'] as String?,
      actorId: row['actor_id'] as String?,
      afterData: row['after_data'] as Map<String, dynamic>?,
      metadata: row['metadata'] as Map<String, dynamic>?,
      createdAt: DateTime.parse(row['created_at'] as String),
    );

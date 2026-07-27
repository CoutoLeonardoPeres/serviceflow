import 'message_template.dart';

/// Registro de comunicação com cliente.
class CommunicationLog {
  const CommunicationLog({
    required this.id,
    required this.channel,
    required this.status,
    required this.createdAt,
    this.customerId,
    this.subject,
    this.bodyPreview,
    this.relatedEntity,
    this.relatedEntityId,
    this.templateId,
  });

  final String id;
  final String? customerId;
  final MessageChannel channel;
  final String status; // sent | draft | failed
  final String? subject;
  final String? bodyPreview;
  final String? relatedEntity;
  final String? relatedEntityId;
  final String? templateId;
  final DateTime createdAt;

  String get statusLabel => switch (status) {
        'sent' => 'Enviado',
        'draft' => 'Rascunho',
        'failed' => 'Falhou',
        _ => status,
      };
}

CommunicationLog communicationLogFromRow(Map<String, dynamic> row) =>
    CommunicationLog(
      id: row['id'] as String,
      customerId: row['customer_id'] as String?,
      channel: messageChannelFromString(row['channel'] as String),
      status: row['status'] as String? ?? 'sent',
      subject: row['subject'] as String?,
      bodyPreview: row['body_preview'] as String?,
      relatedEntity: row['related_entity'] as String?,
      relatedEntityId: row['related_entity_id'] as String?,
      templateId: row['template_id'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
    );

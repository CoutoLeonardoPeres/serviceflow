class TenantBillingWebhookEvent {
  const TenantBillingWebhookEvent({
    required this.id,
    required this.provider,
    required this.providerEventId,
    required this.providerReference,
    required this.eventType,
    required this.processingStatus,
    required this.processingNote,
    required this.checkoutSessionId,
    required this.receivedAt,
    required this.processedAt,
  });

  final String id;
  final String provider;
  final String? providerEventId;
  final String? providerReference;
  final String eventType;
  final String processingStatus;
  final String? processingNote;
  final String? checkoutSessionId;
  final DateTime receivedAt;
  final DateTime? processedAt;

  factory TenantBillingWebhookEvent.fromMap(Map<String, dynamic> map) {
    return TenantBillingWebhookEvent(
      id: map['id'] as String,
      provider: map['provider'] as String? ?? '',
      providerEventId: map['provider_event_id'] as String?,
      providerReference: map['provider_reference'] as String?,
      eventType: map['event_type'] as String? ?? '',
      processingStatus: map['processing_status'] as String? ?? 'received',
      processingNote: map['processing_note'] as String?,
      checkoutSessionId: map['checkout_session_id'] as String?,
      receivedAt: DateTime.parse(map['received_at'] as String),
      processedAt: map['processed_at'] == null
          ? null
          : DateTime.tryParse(map['processed_at'] as String),
    );
  }
}

/// Canal de comunicação suportado.
enum MessageChannel {
  whatsapp,
  email,
  generic,
  phone;

  String get label => switch (this) {
        MessageChannel.whatsapp => 'WhatsApp',
        MessageChannel.email => 'E-mail',
        MessageChannel.generic => 'Geral',
        MessageChannel.phone => 'Ligação',
      };
}

MessageChannel messageChannelFromString(String s) => switch (s) {
      'whatsapp' => MessageChannel.whatsapp,
      'email' => MessageChannel.email,
      'phone' => MessageChannel.phone,
      _ => MessageChannel.generic,
    };

/// Template de mensagem reutilizável.
class MessageTemplate {
  const MessageTemplate({
    required this.id,
    required this.name,
    required this.channel,
    required this.body,
    required this.isActive,
    required this.createdAt,
    this.subject,
  });

  final String id;
  final String name;
  final MessageChannel channel;
  final String? subject;
  final String body;
  final bool isActive;
  final DateTime createdAt;

  /// Substitui variáveis {{key}} por valores do mapa [vars].
  String resolveBody(Map<String, String> vars) {
    var result = body;
    for (final entry in vars.entries) {
      result = result.replaceAll('{{${entry.key}}}', entry.value);
    }
    return result;
  }

  String? resolveSubject(Map<String, String> vars) {
    if (subject == null) return null;
    var result = subject!;
    for (final entry in vars.entries) {
      result = result.replaceAll('{{${entry.key}}}', entry.value);
    }
    return result;
  }

  MessageTemplate copyWith({
    String? name,
    MessageChannel? channel,
    String? subject,
    String? body,
    bool? isActive,
  }) =>
      MessageTemplate(
        id: id,
        name: name ?? this.name,
        channel: channel ?? this.channel,
        subject: subject ?? this.subject,
        body: body ?? this.body,
        isActive: isActive ?? this.isActive,
        createdAt: createdAt,
      );
}

MessageTemplate messageTemplateFromRow(Map<String, dynamic> row) =>
    MessageTemplate(
      id: row['id'] as String,
      name: row['name'] as String,
      channel: messageChannelFromString(row['channel'] as String),
      subject: row['subject'] as String?,
      body: row['body'] as String,
      isActive: row['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(row['created_at'] as String),
    );

/// Variáveis disponíveis por contexto.
abstract class TemplateVars {
  static const customerName = 'customer_name';
  static const companyName = 'company_name';
  static const quotationNumber = 'quotation_number';
  static const workOrderNumber = 'work_order_number';
  static const serviceTitle = 'service_title';
  static const amount = 'amount';
  static const link = 'link';

  static const all = [
    customerName,
    companyName,
    quotationNumber,
    workOrderNumber,
    serviceTitle,
    amount,
    link,
  ];

  static String label(String key) => switch (key) {
        customerName => 'Nome do cliente',
        companyName => 'Nome da empresa',
        quotationNumber => 'Nº do orçamento',
        workOrderNumber => 'Nº da OS',
        serviceTitle => 'Título do serviço',
        amount => r'Valor (R$)',
        link => 'Link público',
        _ => key,
      };
}

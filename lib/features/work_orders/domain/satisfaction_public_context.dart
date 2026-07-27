/// Contexto mínimo devolvido pela pesquisa pública de satisfação.
///
/// Corresponde ao retorno de `get_public_satisfaction_context` (migration 0041).
/// Por decisão de segurança, o RPC devolve apenas o necessário para o cliente
/// saber o que está avaliando — nunca valores, endereço, telefone, e-mail ou
/// qualquer outro dado do cliente.
class SatisfactionPublicContext {
  const SatisfactionPublicContext({
    required this.workOrderNumber,
    required this.serviceTitle,
    required this.companyName,
    required this.alreadyAnswered,
    this.completedAt,
    this.currentRating,
  });

  final int workOrderNumber;
  final String serviceTitle;
  final String companyName;

  /// True quando já existe resposta para esta OS. O cliente pode corrigir a
  /// nota enquanto o link estiver válido.
  final bool alreadyAnswered;

  final DateTime? completedAt;
  final int? currentRating;
}

SatisfactionPublicContext satisfactionPublicContextFromRow(
  Map<String, dynamic> row,
) =>
    SatisfactionPublicContext(
      workOrderNumber: (row['work_order_number'] as num?)?.toInt() ?? 0,
      serviceTitle: row['service_title'] as String? ?? '',
      companyName: row['company_name'] as String? ?? '',
      alreadyAnswered: row['already_answered'] as bool? ?? false,
      completedAt: row['completed_at'] == null
          ? null
          : DateTime.parse(row['completed_at'] as String),
      currentRating: (row['current_rating'] as num?)?.toInt(),
    );

/// Rótulos das notas, usados na tela pública e no registro interno.
String satisfactionRatingLabel(int rating) => switch (rating) {
      1 => 'Muito insatisfeito',
      2 => 'Insatisfeito',
      3 => 'Neutro',
      4 => 'Satisfeito',
      5 => 'Muito satisfeito',
      _ => 'Sem nota',
    };

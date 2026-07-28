/// Resumo de uma importação de tabela de preços.
///
/// Separa "atualizado" de "sem mudança" de propósito: fornecedor que manda a
/// mesma planilha duas vezes deve ver "300 sem mudança", não "300
/// atualizados" — a segunda leitura esconderia que a tabela nova não chegou.
class PriceImportResult {
  const PriceImportResult({
    required this.lines,
    required this.createdProducts,
    required this.createdPrices,
    required this.updatedPrices,
    required this.unchanged,
    required this.errors,
  });

  final int lines;
  final int createdProducts;
  final int createdPrices;
  final int updatedPrices;
  final int unchanged;
  final List<PriceImportError> errors;

  bool get hasErrors => errors.isNotEmpty;
  int get applied => createdPrices + updatedPrices;

  String get summary {
    final parts = <String>[
      if (createdPrices > 0) '$createdPrices novo(s)',
      if (updatedPrices > 0) '$updatedPrices atualizado(s)',
      if (unchanged > 0) '$unchanged sem mudança',
      if (createdProducts > 0) '$createdProducts produto(s) criado(s)',
    ];
    if (parts.isEmpty) return 'Nada foi importado.';
    return parts.join(' · ');
  }
}

class PriceImportError {
  const PriceImportError({
    required this.line,
    required this.reason,
    this.code,
  });

  /// Número da linha no arquivo, como o operador vê no Excel.
  final int line;
  final String? code;
  final String reason;
}

PriceImportResult priceImportResultFromJson(Map<String, dynamic> json) {
  final rawErrors = json['errors'];
  return PriceImportResult(
    lines: (json['lines'] as num?)?.toInt() ?? 0,
    createdProducts: (json['created_products'] as num?)?.toInt() ?? 0,
    createdPrices: (json['created_prices'] as num?)?.toInt() ?? 0,
    updatedPrices: (json['updated_prices'] as num?)?.toInt() ?? 0,
    unchanged: (json['unchanged'] as num?)?.toInt() ?? 0,
    errors: rawErrors is List
        ? rawErrors.map((e) {
            final map = Map<String, dynamic>.from(e as Map);
            return PriceImportError(
              line: (map['line'] as num?)?.toInt() ?? 0,
              code: map['code'] as String?,
              reason: map['reason'] as String? ?? 'Erro não identificado',
            );
          }).toList()
        : const [],
  );
}

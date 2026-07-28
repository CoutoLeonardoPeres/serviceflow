/// Categoria de material ou equipamento (elétrica, CFTV, piscina, gesso…).
///
/// A margem aqui é uma exceção sobre o padrão da empresa; o produto pode ter
/// a sua, mais específica ainda. `null` significa "herda", não "zero" — a
/// diferença importa: zero seria vender a preço de custo.
class MaterialCategory {
  const MaterialCategory({
    required this.id,
    required this.name,
    required this.isActive,
    this.markupPercent,
  });

  final String id;
  final String name;
  final bool isActive;
  final double? markupPercent;

  MaterialCategory copyWith({
    String? name,
    bool? isActive,
    double? markupPercent,
    bool clearMarkup = false,
  }) =>
      MaterialCategory(
        id: id,
        name: name ?? this.name,
        isActive: isActive ?? this.isActive,
        markupPercent: clearMarkup ? null : markupPercent ?? this.markupPercent,
      );
}

MaterialCategory materialCategoryFromRow(Map<String, dynamic> row) =>
    MaterialCategory(
      id: row['id'] as String,
      name: row['name'] as String,
      isActive: row['is_active'] as bool? ?? true,
      markupPercent: (row['markup_percent'] as num?)?.toDouble(),
    );

/// Preço de um fornecedor para um produto do catálogo.
class SupplierPrice {
  const SupplierPrice({
    required this.id,
    required this.supplierId,
    required this.productId,
    required this.priceCents,
    required this.packQuantity,
    required this.minQuantity,
    required this.isActive,
    this.supplierCode,
    this.supplierName,
    this.productName,
    this.validUntil,
    this.updatedAt,
  });

  final String id;
  final String supplierId;
  final String productId;
  final String? supplierCode;
  final String? supplierName;
  final String? productName;
  final int priceCents;
  final num packQuantity;
  final num minQuantity;
  final DateTime? validUntil;
  final bool isActive;
  final DateTime? updatedAt;

  /// Tabela vencida. Continua aparecendo — sumir sem avisar seria pior —, mas
  /// perde a vez no ranking de melhor preço.
  bool get isStale =>
      validUntil != null && validUntil!.isBefore(DateTime.now());

  Map<String, dynamic> toPayload() => {
        'supplier_id': supplierId,
        'product_id': productId,
        'supplier_code': (supplierCode == null || supplierCode!.trim().isEmpty)
            ? null
            : supplierCode!.trim(),
        'price_cents': priceCents,
        'pack_quantity': packQuantity,
        'min_quantity': minQuantity,
        'valid_until': validUntil?.toIso8601String().split('T').first,
        'is_active': isActive,
      };
}

SupplierPrice supplierPriceFromRow(Map<String, dynamic> row) {
  final supplier = row['suppliers'];
  final product = row['products'];
  return SupplierPrice(
    id: row['id'] as String,
    supplierId: row['supplier_id'] as String,
    productId: row['product_id'] as String,
    supplierCode: row['supplier_code'] as String?,
    supplierName:
        supplier is Map<String, dynamic> ? supplier['name'] as String? : null,
    productName:
        product is Map<String, dynamic> ? product['name'] as String? : null,
    priceCents: (row['price_cents'] as num).toInt(),
    packQuantity: (row['pack_quantity'] as num?) ?? 1,
    minQuantity: (row['min_quantity'] as num?) ?? 0,
    validUntil: row['valid_until'] == null
        ? null
        : DateTime.parse(row['valid_until'] as String),
    isActive: row['is_active'] as bool? ?? true,
    updatedAt: row['updated_at'] == null
        ? null
        : DateTime.parse(row['updated_at'] as String),
  );
}

/// Uma linha do ranking de melhor preço, como `best_price_for_product` devolve.
class BestPriceOption {
  const BestPriceOption({
    required this.supplierId,
    required this.supplierName,
    required this.priceCents,
    required this.markupPercent,
    required this.clientPriceCents,
    required this.isStale,
    required this.stockQuantity,
    required this.stockAvgCostCents,
    this.supplierCode,
    this.leadTimeDays,
    this.validUntil,
  });

  final String supplierId;
  final String supplierName;
  final String? supplierCode;
  final int priceCents;
  final double markupPercent;

  /// Preço de repasse ao cliente já com a margem aplicada.
  final int clientPriceCents;
  final int? leadTimeDays;
  final DateTime? validUntil;
  final bool isStale;

  /// Saldo próprio do produto, somando todos os depósitos. Vale para o produto
  /// inteiro, não para esta linha — vem repetido em todas.
  final num stockQuantity;
  final int stockAvgCostCents;

  bool get hasStock => stockQuantity > 0;
}

BestPriceOption bestPriceOptionFromRow(Map<String, dynamic> row) =>
    BestPriceOption(
      supplierId: row['supplier_id'] as String,
      supplierName: row['supplier_name'] as String,
      supplierCode: row['supplier_code'] as String?,
      priceCents: (row['price_cents'] as num).toInt(),
      markupPercent: (row['markup_percent'] as num?)?.toDouble() ?? 0,
      clientPriceCents: (row['client_price_cents'] as num).toInt(),
      leadTimeDays: (row['lead_time_days'] as num?)?.toInt(),
      validUntil: row['valid_until'] == null
          ? null
          : DateTime.parse(row['valid_until'] as String),
      isStale: row['is_stale'] as bool? ?? false,
      stockQuantity: (row['stock_quantity'] as num?) ?? 0,
      stockAvgCostCents: (row['stock_avg_cost_cents'] as num?)?.toInt() ?? 0,
    );

/// Aplica a margem sobre o custo. Espelha o cálculo de
/// `best_price_for_product` (0059) para a tela conseguir prever o repasse sem
/// ida ao banco a cada tecla.
int applyMarkup(int costCents, double markupPercent) =>
    (costCents * (1 + markupPercent / 100)).round();

/// Margem efetiva de um produto, do nível mais específico para o mais geral.
/// `null` em qualquer nível significa "herda do de cima".
double effectiveMarkup({
  double? productMarkup,
  double? categoryMarkup,
  double? tenantDefault,
}) =>
    productMarkup ?? categoryMarkup ?? tenantDefault ?? 0;

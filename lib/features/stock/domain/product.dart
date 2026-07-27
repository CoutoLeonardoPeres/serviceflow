/// Unidade de medida de um produto do catálogo.
///
/// Espelha o CHECK de `products.unit` na migration 0042. Se um valor novo for
/// adicionado no banco, ele precisa entrar aqui também.
enum ProductUnit {
  un,
  m,
  m2,
  m3,
  kg,
  g,
  l,
  ml,
  cx,
  pc,
  h;

  String get value => name;

  String get label => switch (this) {
        ProductUnit.un => 'Unidade',
        ProductUnit.m => 'Metro',
        ProductUnit.m2 => 'Metro quadrado',
        ProductUnit.m3 => 'Metro cúbico',
        ProductUnit.kg => 'Quilograma',
        ProductUnit.g => 'Grama',
        ProductUnit.l => 'Litro',
        ProductUnit.ml => 'Mililitro',
        ProductUnit.cx => 'Caixa',
        ProductUnit.pc => 'Peça',
        ProductUnit.h => 'Hora',
      };

  /// Abreviação usada ao lado de quantidades na UI.
  String get short => switch (this) {
        ProductUnit.un => 'un',
        ProductUnit.m => 'm',
        ProductUnit.m2 => 'm²',
        ProductUnit.m3 => 'm³',
        ProductUnit.kg => 'kg',
        ProductUnit.g => 'g',
        ProductUnit.l => 'L',
        ProductUnit.ml => 'mL',
        ProductUnit.cx => 'cx',
        ProductUnit.pc => 'pç',
        ProductUnit.h => 'h',
      };
}

ProductUnit productUnitFromString(String value) => switch (value) {
      'un' => ProductUnit.un,
      'm' => ProductUnit.m,
      'm2' => ProductUnit.m2,
      'm3' => ProductUnit.m3,
      'kg' => ProductUnit.kg,
      'g' => ProductUnit.g,
      'l' => ProductUnit.l,
      'ml' => ProductUnit.ml,
      'cx' => ProductUnit.cx,
      'pc' => ProductUnit.pc,
      'h' => ProductUnit.h,
      _ => ProductUnit.un,
    };

/// Rastreio de lote/série do produto (ADR-024, migration 0047).
///
/// Opcional e por produto — a maioria dos produtos não rastreia nada.
/// `serial` limita cada movimento a quantidade = 1 e só permite uma "posse"
/// por vez (não pode entrar duas vezes sem ter saído, nem sair sem ter
/// entrado). Sem controle de validade nesta entrega.
enum ProductTrackingType {
  none,
  lot,
  serial;

  String get value => name;

  String get label => switch (this) {
        ProductTrackingType.none => 'Nenhum',
        ProductTrackingType.lot => 'Lote',
        ProductTrackingType.serial => 'Número de série',
      };
}

ProductTrackingType productTrackingTypeFromString(String? value) =>
    switch (value) {
      'lot' => ProductTrackingType.lot,
      'serial' => ProductTrackingType.serial,
      _ => ProductTrackingType.none,
    };

/// Produto do catálogo.
///
/// `trackStock == false` significa que o item existe no catálogo mas não tem
/// saldo — serviços e consumos diretos. O servidor rejeita movimento para
/// esses produtos (migration 0042).
class Product {
  const Product({
    required this.id,
    required this.tenantId,
    required this.name,
    required this.unit,
    required this.trackStock,
    required this.minQuantity,
    required this.isActive,
    required this.createdAt,
    this.trackingType = ProductTrackingType.none,
    this.sku,
    this.description,
  });

  final String id;
  final String tenantId;
  final String name;
  final String? sku;
  final String? description;
  final ProductUnit unit;
  final bool trackStock;
  final ProductTrackingType trackingType;

  /// Quantidade mínima para alerta. Zero desliga o alerta.
  final double minQuantity;

  final bool isActive;
  final DateTime createdAt;

  /// Rótulo com SKU quando houver, para listas e seletores.
  String get displayName =>
      (sku == null || sku!.isEmpty) ? name : '$sku — $name';
}

Product productFromRow(Map<String, dynamic> row) => Product(
      id: row['id'] as String,
      tenantId: row['tenant_id'] as String,
      name: row['name'] as String,
      sku: row['sku'] as String?,
      description: row['description'] as String?,
      unit: productUnitFromString(row['unit'] as String? ?? 'un'),
      trackStock: row['track_stock'] as bool? ?? true,
      trackingType: productTrackingTypeFromString(row['tracking_type'] as String?),
      minQuantity: (row['min_quantity'] as num?)?.toDouble() ?? 0,
      isActive: row['is_active'] as bool? ?? true,
      createdAt: DateTime.parse(row['created_at'] as String),
    );

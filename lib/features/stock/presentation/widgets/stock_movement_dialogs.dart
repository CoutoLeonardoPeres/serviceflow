import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/error/app_error.dart';
import '../../../../core/widgets/app_form_dialog.dart';
import '../../application/stock_notifier.dart';
import '../../domain/product.dart';
import '../../domain/stock_balance.dart';
import '../../domain/warehouse.dart';

/// Abre o diálogo de entrada de estoque.
Future<void> showStockEntryDialog(
  BuildContext context,
  WidgetRef ref, {
  String? productId,
  String? warehouseId,
}) async {
  final saved = await showAppFormDialog<bool>(
    context: context,
    title: 'Entrada de estoque',
    maxWidth: 560,
    child: _StockMovementForm(
      mode: _MovementMode.entry,
      initialProductId: productId,
      initialWarehouseId: warehouseId,
    ),
  );
  if (saved == true) {
    invalidateStockAfterMovement(ref);
  }
}

/// Abre o diálogo de saída, já com produto e depósito definidos pelo saldo.
Future<void> showStockExitDialog(
  BuildContext context,
  WidgetRef ref, {
  required StockBalance balance,
}) async {
  final saved = await showAppFormDialog<bool>(
    context: context,
    title: 'Saída de estoque',
    maxWidth: 560,
    child: _StockMovementForm(
      mode: _MovementMode.exit,
      initialProductId: balance.productId,
      initialWarehouseId: balance.warehouseId,
      availableQuantity: balance.quantity,
    ),
  );
  if (saved == true) {
    invalidateStockAfterMovement(ref);
  }
}

/// Abre o diálogo de ajuste de inventário.
///
/// Exige `stock.adjust`. Se o usuário não tiver a permissão, o servidor rejeita
/// e o erro aparece dentro do próprio diálogo.
Future<void> showStockAdjustmentDialog(
  BuildContext context,
  WidgetRef ref, {
  required StockBalance balance,
}) async {
  final saved = await showAppFormDialog<bool>(
    context: context,
    title: 'Ajuste de inventário',
    maxWidth: 560,
    child: _StockMovementForm(
      mode: _MovementMode.adjustment,
      initialProductId: balance.productId,
      initialWarehouseId: balance.warehouseId,
      availableQuantity: balance.quantity,
    ),
  );
  if (saved == true) {
    invalidateStockAfterMovement(ref);
  }
}

enum _MovementMode { entry, exit, adjustment }

class _StockMovementForm extends ConsumerStatefulWidget {
  const _StockMovementForm({
    required this.mode,
    this.initialProductId,
    this.initialWarehouseId,
    this.availableQuantity,
  });

  final _MovementMode mode;
  final String? initialProductId;
  final String? initialWarehouseId;
  final double? availableQuantity;

  @override
  ConsumerState<_StockMovementForm> createState() => _StockMovementFormState();
}

class _StockMovementFormState extends ConsumerState<_StockMovementForm> {
  final _formKey = GlobalKey<FormState>();
  final _quantityController = TextEditingController();
  final _costController = TextEditingController();
  final _reasonController = TextEditingController();
  final _lotController = TextEditingController();

  String? _productId;
  String? _warehouseId;
  bool _saving = false;
  String? _serverError;
  ProductTrackingType _trackingType = ProductTrackingType.none;

  @override
  void initState() {
    super.initState();
    _productId = widget.initialProductId;
    _warehouseId = widget.initialWarehouseId;
  }

  @override
  void dispose() {
    _quantityController.dispose();
    _costController.dispose();
    _reasonController.dispose();
    _lotController.dispose();
    super.dispose();
  }

  bool get _needsCost => widget.mode == _MovementMode.entry;
  bool get _requiresReason => widget.mode == _MovementMode.adjustment;

  String get _submitLabel => switch (widget.mode) {
        _MovementMode.entry => 'Registrar entrada',
        _MovementMode.exit => 'Registrar saída',
        _MovementMode.adjustment => 'Aplicar ajuste',
      };

  String get _quantityLabel => switch (widget.mode) {
        _MovementMode.adjustment => 'Quantidade contada *',
        _ => 'Quantidade *',
      };

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_productId == null || _warehouseId == null) {
      setState(() => _serverError = 'Escolha o produto e o depósito.');
      return;
    }

    setState(() {
      _saving = true;
      _serverError = null;
    });

    final repo = ref.read(stockRepositoryProvider);
    final quantity = _parseQuantity(_quantityController.text)!;
    final lotCode = _lotOrNull();

    try {
      switch (widget.mode) {
        case _MovementMode.entry:
          await repo.recordEntry(
            productId: _productId!,
            warehouseId: _warehouseId!,
            quantity: quantity,
            unitCostCents: _parseCents(_costController.text) ?? 0,
            reason: _reasonOrNull(),
            lotCode: lotCode,
          );
        case _MovementMode.exit:
          await repo.recordExit(
            productId: _productId!,
            warehouseId: _warehouseId!,
            quantity: quantity,
            reason: _reasonOrNull(),
            lotCode: lotCode,
          );
        case _MovementMode.adjustment:
          await repo.recordAdjustment(
            productId: _productId!,
            warehouseId: _warehouseId!,
            countedQuantity: quantity,
            reason: _reasonController.text.trim(),
            lotCode: lotCode,
          );
      }
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        // A mensagem do servidor para regra de negócio é específica e acionável
        // ("Saldo insuficiente: disponível 3, solicitado 10").
        _serverError =
            e is AppError ? e.userMessage : 'Não foi possível registrar.';
      });
    }
  }

  String? _reasonOrNull() {
    final text = _reasonController.text.trim();
    return text.isEmpty ? null : text;
  }

  String? _lotOrNull() {
    final text = _lotController.text.trim();
    return text.isEmpty ? null : text;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final productsAsync = ref.watch(stockTrackedProductsProvider);
    final warehousesAsync = ref.watch(warehousesProvider);

    return Form(
      key: _formKey,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (widget.availableQuantity != null) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                'Saldo atual: ${_formatQuantity(widget.availableQuantity!)}',
                style: theme.textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Produto — travado quando o diálogo veio de um saldo existente.
          productsAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const Text('Erro ao carregar produtos.'),
            data: (products) {
              final selected =
                  products.where((p) => p.id == _productId).firstOrNull;
              _trackingType = selected?.trackingType ?? ProductTrackingType.none;
              return DropdownButtonFormField<String>(
                initialValue: _productId,
                decoration: const InputDecoration(labelText: 'Produto *'),
                items: products
                    .map((p) => DropdownMenuItem(
                          value: p.id,
                          child: Text(p.displayName),
                        ))
                    .toList(),
                onChanged: widget.initialProductId != null
                    ? null
                    : (v) => setState(() => _productId = v),
                validator: (v) => v == null ? 'Escolha o produto.' : null,
              );
            },
          ),
          const SizedBox(height: 14),

          warehousesAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, __) => const Text('Erro ao carregar depósitos.'),
            data: (warehouses) {
              _warehouseId ??= _defaultWarehouseId(warehouses);
              return DropdownButtonFormField<String>(
                initialValue: _warehouseId,
                decoration: const InputDecoration(labelText: 'Depósito *'),
                items: warehouses
                    .map((w) => DropdownMenuItem(
                          value: w.id,
                          child: Text(w.name),
                        ))
                    .toList(),
                onChanged: widget.initialWarehouseId != null
                    ? null
                    : (v) => setState(() => _warehouseId = v),
                validator: (v) => v == null ? 'Escolha o depósito.' : null,
              );
            },
          ),
          const SizedBox(height: 14),

          TextFormField(
            controller: _quantityController,
            decoration: InputDecoration(
              labelText: _quantityLabel,
              helperText: widget.mode == _MovementMode.adjustment
                  ? 'O saldo passa a ser exatamente esta quantidade.'
                  : null,
            ),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
            ],
            validator: _validateQuantity,
          ),

          if (_needsCost) ...[
            const SizedBox(height: 14),
            TextFormField(
              controller: _costController,
              decoration: const InputDecoration(
                labelText: 'Custo unitário (R\$) *',
                helperText: 'Recalcula o custo médio do saldo.',
              ),
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.,]')),
              ],
              validator: (v) {
                if (_parseCents(v ?? '') == null) {
                  return 'Informe o custo unitário.';
                }
                return null;
              },
            ),
          ],

          if (_trackingType != ProductTrackingType.none) ...[
            const SizedBox(height: 14),
            TextFormField(
              controller: _lotController,
              decoration: InputDecoration(
                labelText: _trackingType == ProductTrackingType.serial
                    ? 'Número de série *'
                    : 'Lote *',
                helperText: widget.mode == _MovementMode.entry
                    ? 'Novo código cria o lote; código existente reutiliza.'
                    : 'Deve ser um código já existente.',
              ),
              validator: (v) {
                if (widget.mode == _MovementMode.adjustment) return null;
                if ((v ?? '').trim().isEmpty) return 'Informe o código.';
                return null;
              },
            ),
          ],

          const SizedBox(height: 14),
          TextFormField(
            controller: _reasonController,
            maxLines: 2,
            maxLength: 500,
            decoration: InputDecoration(
              labelText: _requiresReason ? 'Motivo do ajuste *' : 'Observação',
              alignLabelWithHint: true,
              helperText: _requiresReason
                  ? 'Obrigatório: o ajuste sobrepõe o saldo calculado.'
                  : null,
            ),
            validator: (v) {
              if (!_requiresReason) return null;
              if ((v ?? '').trim().length < 3) {
                return 'Descreva o motivo do ajuste.';
              }
              return null;
            },
          ),

          if (_serverError != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Row(
                children: [
                  Icon(Icons.error_outline,
                      size: 18, color: theme.colorScheme.onErrorContainer),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _serverError!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onErrorContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed:
                    _saving ? null : () => Navigator.of(context).pop(false),
                child: const Text('Cancelar'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(_submitLabel),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String? _defaultWarehouseId(List<Warehouse> warehouses) {
    if (warehouses.isEmpty) return null;
    final def = warehouses.where((w) => w.isDefault);
    return def.isNotEmpty ? def.first.id : warehouses.first.id;
  }

  String? _validateQuantity(String? value) {
    final parsed = _parseQuantity(value ?? '');
    if (parsed == null) return 'Informe a quantidade.';

    // Ajuste pode zerar o saldo; entrada e saída exigem valor positivo.
    if (widget.mode == _MovementMode.adjustment) {
      if (parsed < 0) return 'A quantidade não pode ser negativa.';
      if (widget.availableQuantity != null &&
          parsed == widget.availableQuantity) {
        return 'Igual ao saldo atual — nada a ajustar.';
      }
      return null;
    }

    if (parsed <= 0) return 'A quantidade deve ser maior que zero.';

    // Checagem local só para retorno imediato. A garantia real é do servidor,
    // que trava a linha de saldo antes de decidir (migration 0042).
    if (widget.mode == _MovementMode.exit &&
        widget.availableQuantity != null &&
        parsed > widget.availableQuantity!) {
      return 'Saldo disponível: ${_formatQuantity(widget.availableQuantity!)}.';
    }
    return null;
  }
}

/// Aceita "10", "10,5" e "10.5".
double? _parseQuantity(String raw) {
  final text = raw.trim().replaceAll(',', '.');
  if (text.isEmpty) return null;
  return double.tryParse(text);
}

/// Converte reais digitados para centavos (ADR-017).
int? _parseCents(String raw) {
  final value = _parseQuantity(raw);
  if (value == null || value < 0) return null;
  return (value * 100).round();
}

String _formatQuantity(double value) {
  if (value == value.truncate()) return '${value.truncate()}';
  return value
      .toStringAsFixed(3)
      .replaceAll(RegExp(r'0+$'), '')
      .replaceAll(RegExp(r'\.$'), '');
}

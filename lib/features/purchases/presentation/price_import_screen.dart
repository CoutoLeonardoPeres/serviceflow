import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/error/app_error.dart';
import '../../../core/files/attachment_picker.dart';
import '../../../core/widgets/neomorphic.dart';
import '../../../core/files/text_file_download.dart';
import '../application/purchase_notifier.dart';
import '../domain/price_import_result.dart';
import '../domain/price_sheet.dart';
import '../domain/supplier.dart';

/// Importação da tabela de preços do fornecedor.
///
/// O fluxo é baixar o modelo, mandar ao fornecedor, receber preenchido e
/// importar. A prévia antes de confirmar existe porque preço errado só
/// aparece na proposta do cliente — e aí já foi.
class PriceImportScreen extends ConsumerStatefulWidget {
  const PriceImportScreen({super.key, required this.supplier});

  final Supplier supplier;

  @override
  ConsumerState<PriceImportScreen> createState() => _PriceImportScreenState();
}

class _PriceImportScreenState extends ConsumerState<PriceImportScreen> {
  PriceSheet? _sheet;
  String? _fileName;
  bool _createMissing = true;
  bool _importing = false;
  PriceImportResult? _result;
  String? _error;

  Future<void> _downloadTemplate() async {
    await downloadTextFile(
      fileName: 'modelo-precos-serviceflow.csv',
      content: buildPriceSheetTemplate(),
      mimeType: 'text/csv',
    );
  }

  Future<void> _pickFile() async {
    setState(() {
      _error = null;
      _result = null;
    });

    final picked = await pickAttachments(
      allowDocuments: true,
      allowMultiple: false,
    );
    if (picked == null || picked.isEmpty) return;

    final file = picked.first;
    final bytes = file.bytes;
    if (bytes == null) {
      setState(() => _error = 'Não foi possível ler o arquivo.');
      return;
    }

    // O Excel brasileiro salva em Latin-1 com frequência. Tentar UTF-8 e cair
    // para Latin-1 evita o arquivo virar "Cabo el?trico" sem explicação.
    String content;
    try {
      content = utf8.decode(bytes);
    } on FormatException {
      content = latin1.decode(bytes);
    }

    final sheet = parsePriceSheet(content);
    setState(() {
      _fileName = file.name;
      _sheet = sheet;
    });
  }

  Future<void> _import() async {
    final sheet = _sheet;
    if (sheet == null || !sheet.isUsable) return;

    setState(() {
      _importing = true;
      _error = null;
    });

    try {
      final result = await ref.read(purchaseRepositoryProvider).importSupplierPrices(
            supplierId: widget.supplier.id,
            rows: sheet.validRows,
            createMissing: _createMissing,
          );
      ref.invalidate(supplierPricesProvider(widget.supplier.id));
      if (!mounted) return;
      setState(() {
        _importing = false;
        _result = result;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _importing = false;
        _error = e is AppError ? e.userMessage : 'Não foi possível importar.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sheet = _sheet;

    return Scaffold(
      appBar: AppBar(
        title: Text('Importar preços · ${widget.supplier.displayName}'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          NeomorphicPanel(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Como funciona',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Baixe o modelo, mande para o fornecedor e importe o arquivo '
                  'preenchido. O casamento é pelo código do fornecedor — '
                  'reimportar a mesma planilha atualiza os preços em vez de '
                  'duplicar os produtos.',
                ),
                const SizedBox(height: 8),
                Text(
                  'Se o fornecedor mandar .xlsx, abra no Excel e use '
                  '"Salvar como → CSV". Aceita ponto e vírgula ou vírgula, '
                  'e preço com vírgula decimal.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _downloadTemplate,
                      icon: const Icon(Icons.download_outlined),
                      label: const Text('Baixar modelo'),
                    ),
                    FilledButton.icon(
                      onPressed: _importing ? null : _pickFile,
                      icon: const Icon(Icons.upload_file_outlined),
                      label: const Text('Escolher planilha'),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_fileName != null) ...[
            const SizedBox(height: 12),
            Text(
              'Arquivo: $_fileName',
              style: theme.textTheme.bodySmall,
            ),
          ],
          if (sheet != null && sheet.headerProblems.isNotEmpty) ...[
            const SizedBox(height: 16),
            _Alert(
              color: theme.colorScheme.errorContainer,
              textColor: theme.colorScheme.onErrorContainer,
              title: 'Este arquivo não é o modelo',
              lines: sheet.headerProblems,
            ),
          ],
          if (sheet != null && sheet.headerProblems.isEmpty) ...[
            const SizedBox(height: 16),
            _Preview(
              sheet: sheet,
              createMissing: _createMissing,
              onCreateMissingChanged: (v) =>
                  setState(() => _createMissing = v),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed:
                  (_importing || !sheet.isUsable) ? null : _import,
              icon: _importing
                  ? const SizedBox(
                      height: 18,
                      width: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.playlist_add_check_outlined),
              label: Text(
                'Importar ${sheet.validRows.length} item(ns)',
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 16),
            _Alert(
              color: theme.colorScheme.errorContainer,
              textColor: theme.colorScheme.onErrorContainer,
              title: 'Falha na importação',
              lines: [_error!],
            ),
          ],
          if (_result != null) ...[
            const SizedBox(height: 16),
            _ResultPanel(result: _result!),
          ],
        ],
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({
    required this.sheet,
    required this.createMissing,
    required this.onCreateMissingChanged,
  });

  final PriceSheet sheet;
  final bool createMissing;
  final ValueChanged<bool> onCreateMissingChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = NumberFormat.simpleCurrency(locale: 'pt_BR');
    final preview = sheet.validRows.take(8).toList();

    return NeomorphicPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${sheet.validRows.length} linha(s) prontas'
            '${sheet.invalidRows.isEmpty ? '' : ' · ${sheet.invalidRows.length} com problema'}',
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          if (preview.isNotEmpty) ...[
            for (final row in preview)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 92,
                      child: Text(
                        row.supplierCode,
                        style: theme.textTheme.bodySmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Expanded(
                      child: Text(
                        row.name ?? '(sem nome — usa o produto já cadastrado)',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    Text(
                      currency.format((row.priceCents ?? 0) / 100),
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            if (sheet.validRows.length > preview.length)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '… e mais ${sheet.validRows.length - preview.length} item(ns)',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
          if (sheet.invalidRows.isNotEmpty) ...[
            const SizedBox(height: 14),
            Text(
              'Linhas que não serão importadas',
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: theme.colorScheme.error),
            ),
            const SizedBox(height: 4),
            for (final row in sheet.invalidRows.take(10))
              Text(
                'Linha ${row.line}: ${row.error}',
                style: theme.textTheme.bodySmall,
              ),
            if (sheet.invalidRows.length > 10)
              Text(
                '… e mais ${sheet.invalidRows.length - 10}',
                style: theme.textTheme.bodySmall,
              ),
          ],
          const SizedBox(height: 10),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: createMissing,
            onChanged: onCreateMissingChanged,
            title: const Text('Criar produtos que ainda não existem'),
            subtitle: const Text(
              'Desligado, item fora do catálogo é reportado e ignorado.',
            ),
          ),
        ],
      ),
    );
  }
}

class _ResultPanel extends StatelessWidget {
  const _ResultPanel({required this.result});

  final PriceImportResult result;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return NeomorphicPanel(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                result.hasErrors
                    ? Icons.warning_amber_outlined
                    : Icons.check_circle_outline,
                color: result.hasErrors
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Importação concluída',
                  style: theme.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w800),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(result.summary),
          if (result.unchanged > 0 && result.applied == 0) ...[
            const SizedBox(height: 8),
            Text(
              'Nenhum preço mudou. Se você esperava atualização, confira se o '
              'fornecedor mandou a tabela nova.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (result.hasErrors) ...[
            const SizedBox(height: 12),
            Text(
              '${result.errors.length} linha(s) recusada(s)',
              style: theme.textTheme.labelLarge
                  ?.copyWith(color: theme.colorScheme.error),
            ),
            const SizedBox(height: 4),
            for (final error in result.errors.take(15))
              Text(
                'Linha ${error.line}'
                '${error.code == null ? '' : ' (${error.code})'}: '
                '${error.reason}',
                style: theme.textTheme.bodySmall,
              ),
            if (result.errors.length > 15)
              Text(
                '… e mais ${result.errors.length - 15}',
                style: theme.textTheme.bodySmall,
              ),
          ],
        ],
      ),
    );
  }
}

class _Alert extends StatelessWidget {
  const _Alert({
    required this.color,
    required this.textColor,
    required this.title,
    required this.lines,
  });

  final Color color;
  final Color textColor;
  final String title;
  final List<String> lines;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.labelLarge?.copyWith(color: textColor),
          ),
          const SizedBox(height: 4),
          for (final line in lines)
            Text(
              line,
              style: theme.textTheme.bodySmall?.copyWith(color: textColor),
            ),
        ],
      ),
    );
  }
}

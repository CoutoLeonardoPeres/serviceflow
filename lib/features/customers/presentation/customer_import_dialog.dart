import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/error/app_error.dart';
import '../../../core/widgets/app_form_layout.dart';
import '../../../core/widgets/neomorphic.dart';
import '../application/customer_list_notifier.dart';
import '../data/customer_repository.dart';
import '../domain/customer.dart';
import '../domain/customer_address.dart';
import '../domain/customer_contact.dart';
import '../domain/customer_import.dart';

class CustomerImportDialog extends ConsumerStatefulWidget {
  const CustomerImportDialog({super.key});

  @override
  ConsumerState<CustomerImportDialog> createState() =>
      _CustomerImportDialogState();
}

class _CustomerImportDialogState extends ConsumerState<CustomerImportDialog> {
  String? _fileName;
  CustomerImportPreview? _preview;
  CustomerImportResult? _result;
  bool _isPicking = false;
  bool _isImporting = false;
  String? _errorMessage;

  CustomerRepository get _repo => ref.read(customerRepositoryProvider);

  Future<void> _pickFile() async {
    setState(() {
      _isPicking = true;
      _errorMessage = null;
    });
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['csv'],
        allowMultiple: false,
        withData: true,
      );
      if (!mounted || picked == null || picked.files.isEmpty) return;

      final file = picked.files.single;
      final bytes = file.bytes;
      if (bytes == null) {
        setState(() {
          _errorMessage = 'Nao foi possivel ler o arquivo selecionado.';
        });
        return;
      }

      final text = utf8.decode(bytes, allowMalformed: true);
      setState(() {
        _fileName = file.name;
        _preview = parseCustomerImportCsv(text);
        _result = null;
      });
    } finally {
      if (mounted) {
        setState(() {
          _isPicking = false;
        });
      }
    }
  }

  Future<void> _runImport() async {
    final preview = _preview;
    if (preview == null || preview.rows.isEmpty) return;

    setState(() {
      _isImporting = true;
      _result = null;
      _errorMessage = null;
    });

    try {
      final result = await _importRows(preview.rows, preview.issues);
      if (!mounted) return;
      setState(() {
        _result = result;
      });
    } on AppError catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = error.userMessage;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Falha ao importar clientes.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _isImporting = false;
        });
      }
    }
  }

  Future<CustomerImportResult> _importRows(
    List<CustomerImportRow> rows,
    List<CustomerImportIssue> initialIssues,
  ) async {
    final existing = await _repo.findExistingDocumentAndPhoneConflicts(
      documents: rows
          .map((row) => row.document)
          .whereType<String>()
          .where((value) => value.isNotEmpty)
          .toSet(),
      phones: rows
          .map((row) => row.phone)
          .whereType<String>()
          .where((value) => value.isNotEmpty)
          .toSet(),
    );

    final issues = [...initialIssues];
    final seenDocuments = <String>{...existing.documents};
    final seenPhones = <String>{...existing.phones};
    var importedCount = 0;
    var skippedCount = 0;
    var failedCount = 0;

    for (final row in rows) {
      final document = row.document;
      final phone = row.phone;
      if (document != null && seenDocuments.contains(document)) {
        skippedCount++;
        issues.add(
          CustomerImportIssue(
            rowNumber: row.rowNumber,
            message: 'Linha pulada: CPF/CNPJ ja cadastrado.',
          ),
        );
        continue;
      }
      if (phone != null && seenPhones.contains(phone)) {
        skippedCount++;
        issues.add(
          CustomerImportIssue(
            rowNumber: row.rowNumber,
            message: 'Linha pulada: telefone ja cadastrado.',
          ),
        );
        continue;
      }

      try {
        final created = await _repo.create(
          Customer(
            id: '',
            tenantId: '',
            type: row.type,
            name: row.name,
            tradeName: row.tradeName,
            document: row.document,
            email: row.email,
            phone: row.phone,
            notes: row.notes,
            isActive: true,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
          ),
        );

        if (row.contactName != null && row.contactName!.isNotEmpty) {
          await _repo.addContact(
            CustomerContact(
              id: '',
              tenantId: '',
              customerId: created.id,
              name: row.contactName!,
              phone: row.contactPhone,
              whatsapp: row.contactPhone,
              email: row.email,
              isPrimary: true,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
        }

        final canCreateAddress = row.street != null &&
            row.number != null &&
            row.district != null &&
            row.city != null &&
            row.state != null &&
            row.cep != null;
        if (canCreateAddress) {
          await _repo.addAddress(
            CustomerAddress(
              id: '',
              tenantId: '',
              customerId: created.id,
              label: 'Principal',
              cep: row.cep!,
              street: row.street!,
              number: row.number!,
              complement: row.complement,
              district: row.district!,
              city: row.city!,
              state: row.state!,
              isDefault: true,
              reference: null,
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            ),
          );
        } else if (row.hasAddress) {
          issues.add(
            CustomerImportIssue(
              rowNumber: row.rowNumber,
              message:
                  'Cliente importado sem endereco completo. Edite depois para concluir os campos de endereco.',
            ),
          );
        }

        if (document != null) {
          seenDocuments.add(document);
        }
        if (phone != null) {
          seenPhones.add(phone);
        }
        importedCount++;
      } on BusinessRuleError catch (error) {
        failedCount++;
        issues.add(
          CustomerImportIssue(
            rowNumber: row.rowNumber,
            message: error.userMessage,
          ),
        );
      } on AppError catch (error) {
        failedCount++;
        issues.add(
          CustomerImportIssue(
            rowNumber: row.rowNumber,
            message: error.userMessage,
          ),
        );
      } catch (_) {
        failedCount++;
        issues.add(
          CustomerImportIssue(
            rowNumber: row.rowNumber,
            message: 'Falha inesperada ao importar esta linha.',
          ),
        );
      }
    }

    return CustomerImportResult(
      importedCount: importedCount,
      skippedCount: skippedCount,
      failedCount: failedCount,
      issues: issues,
    );
  }

  @override
  Widget build(BuildContext context) {
    final preview = _preview;
    final result = _result;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            AppFormSection(
              title: 'Arquivo de importacao',
              icon: Icons.upload_file_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Use um CSV com cabecalho. Colunas suportadas: tipo, nome, nome_fantasia, cpf_cnpj, email, telefone, contato, contato_telefone, cep, logradouro, numero, complemento, bairro, cidade, uf e observacoes.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _fileName ?? 'Nenhum arquivo selecionado.',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.icon(
                        onPressed:
                            _isPicking || _isImporting ? null : _pickFile,
                        icon: const Icon(Icons.attach_file_outlined),
                        label: Text(_isPicking ? 'Lendo...' : 'Selecionar CSV'),
                      ),
                    ],
                  ),
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _errorMessage!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 16),
            if (preview != null)
              AppFormSection(
                title: 'Pre-analise',
                icon: Icons.fact_check_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _SummaryChip(
                          label: 'Linhas validas',
                          value: '${preview.rows.length}',
                        ),
                        _SummaryChip(
                          label: 'Pendencias',
                          value: '${preview.issues.length}',
                        ),
                        _SummaryChip(
                          label: 'Separador',
                          value: preview.delimiterLabel == ';' ? ';' : ',',
                        ),
                      ],
                    ),
                    if (preview.issues.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _IssuesList(issues: preview.issues.take(8).toList()),
                    ],
                  ],
                ),
              ),
            if (result != null) ...[
              const SizedBox(height: 16),
              AppFormSection(
                title: 'Resultado da importacao',
                icon: Icons.done_all_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _SummaryChip(
                          label: 'Importados',
                          value: '${result.importedCount}',
                        ),
                        _SummaryChip(
                          label: 'Pulados',
                          value: '${result.skippedCount}',
                        ),
                        _SummaryChip(
                          label: 'Falhas',
                          value: '${result.failedCount}',
                        ),
                      ],
                    ),
                    if (result.issues.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      _IssuesList(issues: result.issues.take(12).toList()),
                    ],
                  ],
                ),
              ),
            ],
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _isImporting
                        ? null
                        : () => Navigator.of(context).pop(false),
                    child: const Text('Fechar'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed:
                        _isImporting || preview == null || preview.rows.isEmpty
                            ? null
                            : _runImport,
                    icon: const Icon(Icons.file_download_done_outlined),
                    label: Text(
                      _isImporting
                          ? 'Importando...'
                          : 'Importar ${preview?.rows.length ?? 0} cliente(s)',
                    ),
                  ),
                ),
              ],
            ),
            if (result != null && result.importedCount > 0) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.tonal(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: const Text('Atualizar lista de clientes'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return NeomorphicInset(
      borderRadius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }
}

class _IssuesList extends StatelessWidget {
  const _IssuesList({required this.issues});

  final List<CustomerImportIssue> issues;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: issues
          .map(
            (issue) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                issue.rowNumber > 0
                    ? 'Linha ${issue.rowNumber}: ${issue.message}'
                    : issue.message,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          )
          .toList(),
    );
  }
}

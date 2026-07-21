import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/utils/validators.dart';
import '../application/customer_form_notifier.dart';
import '../application/customer_list_notifier.dart';
import '../domain/customer.dart';

/// Tela de criação/edição de cliente.
/// Modo criação: [customer] == null.
/// Modo edição: [customer] é o cliente existente.
class CustomerFormScreen extends ConsumerStatefulWidget {
  const CustomerFormScreen({super.key, this.customer});

  final Customer? customer;

  @override
  ConsumerState<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends ConsumerState<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late CustomerType _type;
  late final _nameCtrl;
  late final _tradeNameCtrl;
  late final _documentCtrl;
  late final _emailCtrl;
  late final _phoneCtrl;
  late final _notesCtrl;

  bool get _isEdit => widget.customer != null;

  @override
  void initState() {
    super.initState();
    final c = widget.customer;
    _type = c?.type ?? CustomerType.company;
    _nameCtrl = TextEditingController(text: c?.name);
    _tradeNameCtrl = TextEditingController(text: c?.tradeName);
    _documentCtrl = TextEditingController(text: _formatDoc(c));
    _emailCtrl = TextEditingController(text: c?.email);
    _phoneCtrl = TextEditingController(text: c?.phone);
    _notesCtrl = TextEditingController(text: c?.notes);
  }

  String? _formatDoc(Customer? c) {
    if (c?.document == null) return null;
    final doc = c!.document!;
    if (c.type.usesCpf && doc.length == 11) {
      return '${doc.substring(0,3)}.${doc.substring(3,6)}.${doc.substring(6,9)}-${doc.substring(9)}';
    }
    if (!c.type.usesCpf && doc.length == 14) {
      return '${doc.substring(0,2)}.${doc.substring(2,5)}.${doc.substring(5,8)}/${doc.substring(8,12)}-${doc.substring(12)}';
    }
    return doc;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _tradeNameCtrl.dispose();
    _documentCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _notesCtrl.dispose();
    super.dispose();
  }

  String? _validateDocument(String? v) {
    if (v == null || v.isEmpty) return null; // CPF/CNPJ opcional
    return _type.usesCpf ? validateCpf(v) : validateCnpj(v);
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final notifier = ref.read(customerFormProvider.notifier);
    if (_isEdit) {
      notifier.updateCustomer(
        original: widget.customer!,
        type: _type,
        name: _nameCtrl.text,
        tradeName: _tradeNameCtrl.text,
        document: _documentCtrl.text,
        email: _emailCtrl.text,
        phone: _phoneCtrl.text,
        notes: _notesCtrl.text,
      );
    } else {
      notifier.createCustomer(
        type: _type,
        name: _nameCtrl.text,
        tradeName: _tradeNameCtrl.text,
        document: _documentCtrl.text,
        email: _emailCtrl.text,
        phone: _phoneCtrl.text,
        notes: _notesCtrl.text,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(customerFormProvider);
    final isLoading = formState is CustomerFormLoading;

    ref.listen<CustomerFormState>(customerFormProvider, (_, next) {
      if (next is CustomerFormSuccess) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(next.isCreate
                ? 'Cliente criado com sucesso!'
                : 'Cliente atualizado com sucesso!'),
          ),
        );
        ref.read(customerFormProvider.notifier).reset();
        context.pop();
      }
      if (next is CustomerFormError) {
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(next.error.userMessage),
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
          );
        ref.read(customerFormProvider.notifier).reset();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEdit ? 'Editar cliente' : 'Novo cliente'),
        actions: [
          TextButton(
            onPressed: isLoading ? null : _submit,
            child: const Text('Salvar'),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // ── Tipo ───────────────────────────────────────────────────
              Text(
                'Tipo de cliente',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<CustomerType>(
                segments: CustomerType.values
                    .map((t) => ButtonSegment(
                          value: t,
                          label: Text(t.label),
                        ))
                    .toList(),
                selected: {_type},
                onSelectionChanged: isLoading
                    ? null
                    : (s) {
                        setState(() {
                          _type = s.first;
                          _documentCtrl.clear(); // limpa ao trocar tipo
                        });
                      },
                multiSelectionEnabled: false,
              ),
              const SizedBox(height: 20),

              // ── Nome ───────────────────────────────────────────────────
              TextFormField(
                controller: _nameCtrl,
                textCapitalization: TextCapitalization.words,
                decoration: InputDecoration(
                  labelText: 'Nome *',
                  hintText: _type.usesCpf
                      ? 'Nome completo'
                      : 'Razão social',
                ),
                validator: (v) => validateRequired(v, 'Nome'),
                enabled: !isLoading,
              ),
              const SizedBox(height: 12),

              // Nome fantasia (apenas PJ)
              if (!_type.usesCpf) ...[
                TextFormField(
                  controller: _tradeNameCtrl,
                  textCapitalization: TextCapitalization.words,
                  decoration:
                      const InputDecoration(labelText: 'Nome fantasia'),
                  enabled: !isLoading,
                ),
                const SizedBox(height: 12),
              ],

              // ── Documento ──────────────────────────────────────────────
              TextFormField(
                controller: _documentCtrl,
                decoration: InputDecoration(
                  labelText: _type.usesCpf ? 'CPF' : 'CNPJ',
                  hintText:
                      _type.usesCpf ? '000.000.000-00' : '00.000.000/0000-00',
                ),
                keyboardType: TextInputType.number,
                validator: _validateDocument,
                enabled: !isLoading,
              ),
              const SizedBox(height: 12),

              // ── E-mail ─────────────────────────────────────────────────
              TextFormField(
                controller: _emailCtrl,
                decoration: const InputDecoration(labelText: 'E-mail'),
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                validator: (v) =>
                    v != null && v.isNotEmpty ? validateEmail(v) : null,
                enabled: !isLoading,
              ),
              const SizedBox(height: 12),

              // ── Telefone ───────────────────────────────────────────────
              TextFormField(
                controller: _phoneCtrl,
                decoration: const InputDecoration(
                  labelText: 'Telefone',
                  hintText: '(11) 99999-9999',
                ),
                keyboardType: TextInputType.phone,
                validator: validatePhone,
                enabled: !isLoading,
              ),
              const SizedBox(height: 12),

              // ── Observações ────────────────────────────────────────────
              TextFormField(
                controller: _notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Observações internas',
                  alignLabelWithHint: true,
                ),
                maxLines: 3,
                enabled: !isLoading,
              ),
              const SizedBox(height: 32),

              // ── Botão salvar ───────────────────────────────────────────
              ElevatedButton(
                onPressed: isLoading ? null : _submit,
                child: isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5),
                      )
                    : Text(_isEdit ? 'Salvar alterações' : 'Criar cliente'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

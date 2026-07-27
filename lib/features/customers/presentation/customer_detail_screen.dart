import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/location/address_geocoder.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/address_location_box.dart';
import '../../../core/widgets/app_form_dialog.dart';
import '../../../core/widgets/app_form_layout.dart';
import '../../../core/widgets/error_view.dart';
import '../../../shared/providers/tenant_provider.dart';
import '../../communications/presentation/send_message_panel.dart';
import '../application/customer_form_notifier.dart';
import '../application/customer_list_notifier.dart';
import '../domain/customer.dart';
import '../domain/customer_address.dart';
import '../domain/customer_contact.dart';
import 'customer_form_screen.dart';
import 'widgets/customer_type_chip.dart';

class CustomerDetailScreen extends ConsumerStatefulWidget {
  const CustomerDetailScreen({super.key, required this.customerId});

  final String customerId;

  @override
  ConsumerState<CustomerDetailScreen> createState() =>
      _CustomerDetailScreenState();
}

class _CustomerDetailScreenState extends ConsumerState<CustomerDetailScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final customerAsync = ref.watch(customerDetailProvider(widget.customerId));

    return customerAsync.when(
      loading: () => Scaffold(
        appBar: AppBar(title: const Text('Cliente')),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('Cliente')),
        body: ErrorView(
          message: e.toString(),
          onRetry: () =>
              ref.invalidate(customerDetailProvider(widget.customerId)),
        ),
      ),
      data: (customer) => _buildScaffold(context, customer),
    );
  }

  Widget _buildScaffold(BuildContext context, Customer customer) {
    return Scaffold(
      appBar: AppBar(
        title:
            Text(customer.name, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          TextButton.icon(
            onPressed: () => _openEditCustomerDialog(context, customer),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Editar cliente'),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) => _handleAction(context, value, customer),
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  leading: Icon(Icons.edit_outlined),
                  title: Text('Editar'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: customer.isActive ? 'deactivate' : 'reactivate',
                child: ListTile(
                  leading: Icon(
                    customer.isActive
                        ? Icons.block_outlined
                        : Icons.check_circle_outline,
                  ),
                  title: Text(customer.isActive ? 'Desativar' : 'Reativar'),
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
        bottom: TabBar(
          controller: _tabCtrl,
          tabs: const [
            Tab(icon: Icon(Icons.info_outline), text: 'Dados'),
            Tab(icon: Icon(Icons.contacts_outlined), text: 'Contatos'),
            Tab(icon: Icon(Icons.location_on_outlined), text: 'Endereços'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          _DataTab(customer: customer),
          _ContactsTab(customerId: widget.customerId),
          _AddressesTab(customerId: widget.customerId),
        ],
      ),
    );
  }

  Future<void> _openEditCustomerDialog(
    BuildContext context,
    Customer customer,
  ) async {
    final updated = await showAppFormDialog<bool>(
      context: context,
      title: 'Editar cliente',
      child: CustomerFormScreen(customer: customer, embedded: true),
    );
    if (updated == true && mounted) {
      ref.invalidate(customerDetailProvider(customer.id));
      ref.read(customerListProvider.notifier).refresh();
    }
  }

  Future<void> _handleAction(
      BuildContext context, String action, Customer customer) async {
    switch (action) {
      case 'edit':
        await _openEditCustomerDialog(context, customer);
      case 'deactivate':
        final confirm = await _confirmDialog(
          context,
          title: 'Desativar cliente',
          message:
              'Deseja desativar "${customer.name}"? Ele não aparecerá em novas buscas.',
          confirmLabel: 'Desativar',
          isDestructive: true,
        );
        if (confirm == true && mounted) {
          await ref
              .read(customerFormProvider.notifier)
              .deactivateCustomer(customer);
          if (context.mounted) Navigator.of(context).pop();
        }
      case 'reactivate':
        await ref.read(customerRepositoryProvider).reactivate(customer.id);
        ref.invalidate(customerDetailProvider(customer.id));
    }
  }

  Future<bool?> _confirmDialog(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmLabel,
    bool isDestructive = false,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => ctx.pop(false),
            child: const Text('Cancelar'),
          ),
          TextButton(
            style: isDestructive
                ? TextButton.styleFrom(
                    foregroundColor: Theme.of(ctx).colorScheme.error)
                : null,
            onPressed: () => ctx.pop(true),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );
  }
}

// ── Aba: Dados gerais ─────────────────────────────────────────────────────────

class _DataTab extends StatelessWidget {
  const _DataTab({required this.customer});

  final Customer customer;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final df = DateFormat('dd/MM/yyyy', 'pt_BR');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Status
        if (!customer.isActive)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: colorScheme.errorContainer,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.block,
                    color: colorScheme.onErrorContainer, size: 18),
                const SizedBox(width: 8),
                Text(
                  'Cliente inativo',
                  style: TextStyle(
                    color: colorScheme.onErrorContainer,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),

        CustomerTypeChip(type: customer.type),
        const SizedBox(height: 16),
        _InfoRow(label: 'Nome', value: customer.name),
        if (customer.tradeName != null)
          _InfoRow(label: 'Nome fantasia', value: customer.tradeName!),
        if (customer.document != null)
          _InfoRow(
            label: customer.type.usesCpf ? 'CPF' : 'CNPJ',
            value: _formatDocument(customer.document!, customer.type.usesCpf),
          ),
        if (customer.email != null)
          _InfoRow(
            label: 'E-mail',
            value: customer.email!,
            icon: Icons.email_outlined,
          ),
        if (customer.phone != null)
          _InfoRow(
            label: 'Telefone',
            value: _formatPhone(customer.phone!),
            icon: Icons.phone_outlined,
          ),
        if (customer.notes != null && customer.notes!.isNotEmpty)
          _InfoRow(label: 'Observações', value: customer.notes!),
        if (customer.phone != null || customer.email != null) ...[
          const SizedBox(height: 12),
          Consumer(builder: (context, ref, _) {
            final tenant = ref.watch(currentTenantProvider);
            return SendMessageButton(
              messageContext: MessageContext(
                customerId: customer.id,
                customerName: customer.name,
                customerPhone: customer.phone ?? '',
                customerEmail: customer.email ?? '',
                companyName: tenant?['name'] as String? ?? '',
              ),
            );
          }),
        ],
        const Divider(height: 32),
        _InfoRow(
          label: 'Cadastrado em',
          value: df.format(customer.createdAt.toLocal()),
        ),
        _InfoRow(
          label: 'Última atualização',
          value: df.format(customer.updatedAt.toLocal()),
        ),
      ],
    );
  }

  String _formatDocument(String doc, bool isCpf) {
    if (isCpf && doc.length == 11) {
      return '${doc.substring(0, 3)}.${doc.substring(3, 6)}.${doc.substring(6, 9)}-${doc.substring(9)}';
    }
    if (!isCpf && doc.length == 14) {
      return '${doc.substring(0, 2)}.${doc.substring(2, 5)}.${doc.substring(5, 8)}/${doc.substring(8, 12)}-${doc.substring(12)}';
    }
    return doc;
  }

  String _formatPhone(String phone) {
    if (phone.length == 11) {
      return '(${phone.substring(0, 2)}) ${phone.substring(2, 7)}-${phone.substring(7)}';
    }
    if (phone.length == 10) {
      return '(${phone.substring(0, 2)}) ${phone.substring(2, 6)}-${phone.substring(6)}';
    }
    return phone;
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.label, required this.value, this.icon});

  final String label;
  final String value;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 2),
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon,
                    size: 16, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 6),
              ],
              Expanded(
                child: Text(
                  value,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Aba: Contatos ─────────────────────────────────────────────────────────────

class _ContactsTab extends ConsumerWidget {
  const _ContactsTab({required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final contactsAsync = ref.watch(customerContactsProvider(customerId));

    return contactsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(
        message: 'Erro ao carregar contatos.',
        onRetry: () => ref.invalidate(customerContactsProvider(customerId)),
      ),
      data: (contacts) {
        if (contacts.isEmpty) {
          return EmptyView(
            icon: Icons.contacts_outlined,
            message: 'Nenhum contato cadastrado.',
            actionWidget: _AddContactButton(customerId: customerId),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: contacts.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            if (i == contacts.length) {
              return _AddContactButton(customerId: customerId);
            }
            final contact = contacts[i];
            return _ContactCard(
              contact: contact,
              onEdit: () => _showContactForm(context, ref, customerId, contact),
              onDelete: () => _deleteContact(context, ref, contact),
            );
          },
        );
      },
    );
  }

  void _showContactForm(
    BuildContext context,
    WidgetRef ref,
    String customerId,
    CustomerContact? contact,
  ) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => _ContactForm(
        customerId: customerId,
        existing: contact,
        onSaved: () {
          ref.invalidate(customerContactsProvider(customerId));
          Navigator.of(ctx).pop();
        },
      ),
    );
  }

  Future<void> _deleteContact(
    BuildContext context,
    WidgetRef ref,
    CustomerContact contact,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover contato'),
        content: Text('Deseja remover "${contact.name}"?'),
        actions: [
          TextButton(
              onPressed: () => ctx.pop(false), child: const Text('Cancelar')),
          TextButton(
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => ctx.pop(true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      final repo = ref.read(customerRepositoryProvider);
      await repo.deleteContact(contact.id);
      ref.invalidate(customerContactsProvider(customerId));
    }
  }
}

class _ContactCard extends StatelessWidget {
  const _ContactCard({
    required this.contact,
    required this.onEdit,
    required this.onDelete,
  });

  final CustomerContact contact;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: CircleAvatar(child: Text(contact.name[0].toUpperCase())),
        title: Row(
          children: [
            Text(contact.name),
            if (contact.isPrimary) ...[
              const SizedBox(width: 8),
              const Icon(Icons.star, size: 14, color: Colors.amber),
            ],
          ],
        ),
        subtitle: Text([
          if (contact.role != null) contact.role!,
          if (contact.phone != null) contact.phone!,
          if (contact.email != null) contact.email!,
        ].join(' · ')),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'edit') onEdit();
            if (v == 'delete') onDelete();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('Editar')),
            PopupMenuItem(value: 'delete', child: Text('Remover')),
          ],
        ),
      ),
    );
  }
}

class _AddContactButton extends StatelessWidget {
  const _AddContactButton({required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => Consumer(
          builder: (_, ref, __) => _ContactForm(
            customerId: customerId,
            onSaved: () {
              ref.invalidate(customerContactsProvider(customerId));
              Navigator.of(ctx).pop();
            },
          ),
        ),
      ),
      icon: const Icon(Icons.add),
      label: const Text('Adicionar contato'),
    );
  }
}

// ── Formulário de contato (bottom sheet) ──────────────────────────────────────

class _ContactForm extends ConsumerStatefulWidget {
  const _ContactForm({
    required this.customerId,
    required this.onSaved,
    this.existing,
  });

  final String customerId;
  final CustomerContact? existing;
  final VoidCallback onSaved;

  @override
  ConsumerState<_ContactForm> createState() => _ContactFormState();
}

class _ContactFormState extends ConsumerState<_ContactForm> {
  final _formKey = GlobalKey<FormState>();
  late final _nameCtrl = TextEditingController(text: widget.existing?.name);
  late final _roleCtrl = TextEditingController(text: widget.existing?.role);
  late final _phoneCtrl = TextEditingController(text: widget.existing?.phone);
  late final _whatsappCtrl =
      TextEditingController(text: widget.existing?.whatsapp);
  late final _emailCtrl = TextEditingController(text: widget.existing?.email);
  late bool _isPrimary = widget.existing?.isPrimary ?? false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _roleCtrl.dispose();
    _phoneCtrl.dispose();
    _whatsappCtrl.dispose();
    _emailCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(customerContactFormProvider);
    final isLoading = formState is ContactFormLoading;

    ref.listen<ContactFormState>(customerContactFormProvider, (_, next) {
      if (next is ContactFormSuccess) {
        ref.read(customerContactFormProvider.notifier).reset();
        widget.onSaved();
      }
      if (next is ContactFormError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.error.userMessage)),
        );
        ref.read(customerContactFormProvider.notifier).reset();
      }
    });

    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
      ),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppFormSection(
              title:
                  widget.existing == null ? 'Novo contato' : 'Editar contato',
              icon: Icons.contact_phone_outlined,
              child: AppFormGrid(
                children: [
                  TextFormField(
                    controller: _nameCtrl,
                    decoration: const InputDecoration(labelText: 'Nome *'),
                    validator: (v) => validateRequired(v, 'Nome'),
                    enabled: !isLoading,
                  ),
                  TextFormField(
                    controller: _roleCtrl,
                    decoration:
                        const InputDecoration(labelText: 'Cargo / Função'),
                    enabled: !isLoading,
                  ),
                  TextFormField(
                    controller: _phoneCtrl,
                    decoration: const InputDecoration(labelText: 'Telefone'),
                    keyboardType: TextInputType.phone,
                    validator: validatePhone,
                    enabled: !isLoading,
                  ),
                  TextFormField(
                    controller: _emailCtrl,
                    decoration: const InputDecoration(labelText: 'E-mail'),
                    keyboardType: TextInputType.emailAddress,
                    validator: (v) =>
                        v != null && v.isNotEmpty ? validateEmail(v) : null,
                    enabled: !isLoading,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SwitchListTile(
              title: const Text('Contato principal'),
              value: _isPrimary,
              onChanged:
                  isLoading ? null : (v) => setState(() => _isPrimary = v),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: isLoading ? null : _submit,
              child: isLoading
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    ref.read(customerContactFormProvider.notifier).save(
          existing: widget.existing,
          customerId: widget.customerId,
          name: _nameCtrl.text,
          role: _roleCtrl.text,
          phone: _phoneCtrl.text,
          whatsapp: _whatsappCtrl.text,
          email: _emailCtrl.text,
          isPrimary: _isPrimary,
        );
  }
}

// ── Aba: Endereços ────────────────────────────────────────────────────────────

class _AddressesTab extends ConsumerWidget {
  const _AddressesTab({required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final addressesAsync = ref.watch(customerAddressesProvider(customerId));

    return addressesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => ErrorView(
        message: 'Erro ao carregar endereços.',
        onRetry: () => ref.invalidate(customerAddressesProvider(customerId)),
      ),
      data: (addresses) {
        if (addresses.isEmpty) {
          return EmptyView(
            icon: Icons.location_on_outlined,
            message: 'Nenhum endereço cadastrado.',
            actionWidget: _AddAddressButton(customerId: customerId),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: addresses.length + 1,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, i) {
            if (i == addresses.length) {
              return _AddAddressButton(customerId: customerId);
            }
            final addr = addresses[i];
            return _AddressCard(
              address: addr,
              onEdit: () => _showAddressForm(context, ref, customerId, addr),
              onDelete: () => _deleteAddress(context, ref, addr),
            );
          },
        );
      },
    );
  }

  void _showAddressForm(
    BuildContext context,
    WidgetRef ref,
    String customerId,
    CustomerAddress? address,
  ) {
    Navigator.of(context).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => Consumer(
          builder: (_, r, __) => _AddressFormScreen(
            customerId: customerId,
            existing: address,
            onSaved: () {
              r.invalidate(customerAddressesProvider(customerId));
              Navigator.of(context).pop();
            },
          ),
        ),
      ),
    );
  }

  Future<void> _deleteAddress(
    BuildContext context,
    WidgetRef ref,
    CustomerAddress address,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remover endereço'),
        content: Text('Deseja remover o endereço "${address.label}"?'),
        actions: [
          TextButton(
              onPressed: () => ctx.pop(false), child: const Text('Cancelar')),
          TextButton(
            style: TextButton.styleFrom(
                foregroundColor: Theme.of(ctx).colorScheme.error),
            onPressed: () => ctx.pop(true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ref.read(customerRepositoryProvider).deleteAddress(address.id);
      ref.invalidate(customerAddressesProvider(customerId));
    }
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({
    required this.address,
    required this.onEdit,
    required this.onDelete,
  });

  final CustomerAddress address;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      child: ListTile(
        leading: const Icon(Icons.location_on_outlined),
        title: Row(
          children: [
            Text(address.label),
            if (address.isDefault) ...[
              const SizedBox(width: 8),
              const Icon(Icons.star, size: 14, color: Colors.amber),
            ],
          ],
        ),
        subtitle: Text(address.oneLineAddress),
        trailing: PopupMenuButton<String>(
          onSelected: (v) {
            if (v == 'edit') onEdit();
            if (v == 'delete') onDelete();
          },
          itemBuilder: (_) => const [
            PopupMenuItem(value: 'edit', child: Text('Editar')),
            PopupMenuItem(value: 'delete', child: Text('Remover')),
          ],
        ),
      ),
    );
  }
}

class _AddAddressButton extends StatelessWidget {
  const _AddAddressButton({required this.customerId});

  final String customerId;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => Consumer(
            builder: (_, ref, __) => _AddressFormScreen(
              customerId: customerId,
              onSaved: () {
                ref.invalidate(customerAddressesProvider(customerId));
                Navigator.of(context).pop();
              },
            ),
          ),
        ),
      ),
      icon: const Icon(Icons.add),
      label: const Text('Adicionar endereço'),
    );
  }
}

// ── Tela de formulário de endereço ────────────────────────────────────────────

class _AddressFormScreen extends ConsumerStatefulWidget {
  const _AddressFormScreen({
    required this.customerId,
    required this.onSaved,
    this.existing,
  });

  final String customerId;
  final CustomerAddress? existing;
  final VoidCallback onSaved;

  @override
  ConsumerState<_AddressFormScreen> createState() => _AddressFormScreenState();
}

class _AddressFormScreenState extends ConsumerState<_AddressFormScreen> {
  final _formKey = GlobalKey<FormState>();
  late final _labelCtrl =
      TextEditingController(text: widget.existing?.label ?? 'Principal');
  late final _cepCtrl = TextEditingController(text: widget.existing?.cep);
  late final _streetCtrl = TextEditingController(text: widget.existing?.street);
  late final _numberCtrl = TextEditingController(text: widget.existing?.number);
  late final _complementCtrl =
      TextEditingController(text: widget.existing?.complement);
  late final _districtCtrl =
      TextEditingController(text: widget.existing?.district);
  late final _cityCtrl = TextEditingController(text: widget.existing?.city);
  late final _referenceCtrl =
      TextEditingController(text: widget.existing?.reference);
  late String _state = widget.existing?.state ?? 'SP';
  late bool _isDefault = widget.existing?.isDefault ?? false;
  late double? _latitude = widget.existing?.latitude;
  late double? _longitude = widget.existing?.longitude;
  bool _isGeocoding = false;

  @override
  void dispose() {
    _labelCtrl.dispose();
    _cepCtrl.dispose();
    _streetCtrl.dispose();
    _numberCtrl.dispose();
    _complementCtrl.dispose();
    _districtCtrl.dispose();
    _cityCtrl.dispose();
    _referenceCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(customerAddressFormProvider);
    final isLoading = formState is AddressFormLoading;

    ref.listen<AddressFormState>(customerAddressFormProvider, (_, next) {
      if (next is AddressFormSuccess) {
        ref.read(customerAddressFormProvider.notifier).reset();
        widget.onSaved();
      }
      if (next is AddressFormError) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(next.error.userMessage)),
        );
        ref.read(customerAddressFormProvider.notifier).reset();
      }
    });

    return Scaffold(
      appBar: AppBar(
        title:
            Text(widget.existing == null ? 'Novo endereço' : 'Editar endereço'),
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
              AppFormSection(
                title: 'Endereço',
                icon: Icons.location_on_outlined,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppFormGrid(
                      children: [
                        TextFormField(
                          controller: _labelCtrl,
                          decoration: const InputDecoration(
                            labelText: 'Rótulo *',
                            hintText: 'Ex.: Sede, Filial, Residência',
                          ),
                          validator: (v) => validateRequired(v, 'Rótulo'),
                          enabled: !isLoading,
                        ),
                        TextFormField(
                          controller: _cepCtrl,
                          decoration: const InputDecoration(labelText: 'CEP *'),
                          keyboardType: TextInputType.number,
                          validator: validateCep,
                          enabled: !isLoading,
                        ),
                        TextFormField(
                          controller: _streetCtrl,
                          decoration:
                              const InputDecoration(labelText: 'Rua / Av. *'),
                          validator: (v) => validateRequired(v, 'Rua'),
                          enabled: !isLoading,
                        ),
                        TextFormField(
                          controller: _numberCtrl,
                          decoration:
                              const InputDecoration(labelText: 'Número *'),
                          validator: (v) => validateRequired(v, 'Número'),
                          enabled: !isLoading,
                        ),
                        TextFormField(
                          controller: _complementCtrl,
                          decoration:
                              const InputDecoration(labelText: 'Complemento'),
                          enabled: !isLoading,
                        ),
                        TextFormField(
                          controller: _districtCtrl,
                          decoration:
                              const InputDecoration(labelText: 'Bairro *'),
                          validator: (v) => validateRequired(v, 'Bairro'),
                          enabled: !isLoading,
                        ),
                        TextFormField(
                          controller: _cityCtrl,
                          decoration:
                              const InputDecoration(labelText: 'Cidade *'),
                          validator: (v) => validateRequired(v, 'Cidade'),
                          enabled: !isLoading,
                        ),
                        DropdownButtonFormField<String>(
                          initialValue: _state,
                          decoration: const InputDecoration(labelText: 'UF *'),
                          items: kBrazilianStates
                              .map((uf) => DropdownMenuItem(
                                    value: uf,
                                    child: Text(uf),
                                  ))
                              .toList(),
                          onChanged: isLoading
                              ? null
                              : (v) => setState(() => _state = v ?? 'SP'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _referenceCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Ponto de referência',
                        hintText: 'Ex.: Próximo ao supermercado X',
                      ),
                      enabled: !isLoading,
                    ),
                    const SizedBox(height: 14),
                    AddressLocationBox(
                      latitude: _latitude,
                      longitude: _longitude,
                      isLoading: _isGeocoding,
                      onLocate:
                          isLoading || _isGeocoding ? null : _lookupCoordinates,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                title: const Text('Endereço padrão'),
                value: _isDefault,
                onChanged:
                    isLoading ? null : (v) => setState(() => _isDefault = v),
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: isLoading ? null : _submit,
                child: isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Salvar endereço'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    ref.read(customerAddressFormProvider.notifier).save(
          existing: widget.existing,
          customerId: widget.customerId,
          label: _labelCtrl.text,
          cep: _cepCtrl.text,
          street: _streetCtrl.text,
          number: _numberCtrl.text,
          complement: _complementCtrl.text,
          district: _districtCtrl.text,
          city: _cityCtrl.text,
          state_: _state,
          reference: _referenceCtrl.text,
          latitude: _latitude,
          longitude: _longitude,
          isDefault: _isDefault,
        );
  }

  Future<void> _lookupCoordinates() async {
    final requiredFields = [
      _streetCtrl.text,
      _numberCtrl.text,
      _cityCtrl.text,
      _state,
    ];
    final hasRequiredAddress =
        requiredFields.every((field) => field.trim().isNotEmpty);
    if (!hasRequiredAddress) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Preencha rua, número, cidade e UF para localizar.'),
        ),
      );
      return;
    }

    setState(() => _isGeocoding = true);
    try {
      final coordinates = await const AddressGeocoder().locate(
        street: _streetCtrl.text,
        number: _numberCtrl.text,
        district: _districtCtrl.text,
        city: _cityCtrl.text,
        state: _state,
        cep: _cepCtrl.text,
      );
      if (!mounted) return;
      setState(() {
        _latitude = coordinates.latitude;
        _longitude = coordinates.longitude;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Endereço localizado no mapa.')),
      );
    } on AddressGeocoderException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } finally {
      if (mounted) setState(() => _isGeocoding = false);
    }
  }
}

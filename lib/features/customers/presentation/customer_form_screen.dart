import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../../core/location/address_geocoder.dart';
import '../../../core/location/cep_lookup.dart';
import '../../../core/utils/validators.dart';
import '../../../core/widgets/address_location_box.dart';
import '../../../core/widgets/app_form_layout.dart';
import '../application/customer_form_notifier.dart';
import '../application/customer_list_notifier.dart';
import '../domain/customer.dart';
import '../domain/customer_address.dart';

/// Tela de criação/edição de cliente.
/// Modo criação: [customer] == null.
/// Modo edição: [customer] é o cliente existente.
class CustomerFormScreen extends ConsumerStatefulWidget {
  const CustomerFormScreen({
    super.key,
    this.customer,
    this.embedded = false,
    this.returnCreatedCustomerOnCreate = false,
  });

  final Customer? customer;
  final bool embedded;
  final bool returnCreatedCustomerOnCreate;

  @override
  ConsumerState<CustomerFormScreen> createState() => _CustomerFormScreenState();
}

class _CustomerFormScreenState extends ConsumerState<CustomerFormScreen> {
  final _formKey = GlobalKey<FormState>();

  late CustomerType _type;
  late final TextEditingController _nameCtrl;
  late final TextEditingController _tradeNameCtrl;
  late final TextEditingController _documentCtrl;
  late final TextEditingController _emailCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _notesCtrl;
  late final TextEditingController _contactNameCtrl;
  late final TextEditingController _contactPhoneCtrl;
  late final TextEditingController _contactEmailCtrl;
  late final TextEditingController _cepCtrl;
  late final TextEditingController _streetCtrl;
  late final TextEditingController _numberCtrl;
  late final TextEditingController _complementCtrl;
  late final TextEditingController _districtCtrl;
  late final TextEditingController _cityCtrl;
  late final TextEditingController _referenceCtrl;
  String _stateUf = 'SP';
  bool _contactNameEdited = false;
  bool _contactPhoneEdited = false;
  bool _isCepLoading = false;
  bool _isGeocoding = false;
  bool _didLoadExistingAddress = false;
  String? _lastCepLookup;
  double? _addressLatitude;
  double? _addressLongitude;

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
    _phoneCtrl = TextEditingController(text: _formatPhone(c?.phone ?? ''));
    _notesCtrl = TextEditingController(text: c?.notes);
    _contactNameCtrl = TextEditingController(text: c?.name);
    _contactPhoneCtrl =
        TextEditingController(text: _formatPhone(c?.phone ?? ''));
    _contactEmailCtrl = TextEditingController(text: c?.email);
    _cepCtrl = TextEditingController();
    _streetCtrl = TextEditingController();
    _numberCtrl = TextEditingController();
    _complementCtrl = TextEditingController();
    _districtCtrl = TextEditingController();
    _cityCtrl = TextEditingController();
    _referenceCtrl = TextEditingController();

    _nameCtrl.addListener(_syncContactName);
    _phoneCtrl.addListener(_syncContactPhone);
  }

  String? _formatDoc(Customer? c) {
    if (c?.document == null) return null;
    final doc = c!.document!;
    if (c.type.usesCpf && doc.length == 11) {
      return '${doc.substring(0, 3)}.${doc.substring(3, 6)}.${doc.substring(6, 9)}-${doc.substring(9)}';
    }
    if (!c.type.usesCpf && doc.length == 14) {
      return '${doc.substring(0, 2)}.${doc.substring(2, 5)}.${doc.substring(5, 8)}/${doc.substring(8, 12)}-${doc.substring(12)}';
    }
    return doc;
  }

  @override
  void dispose() {
    _nameCtrl.removeListener(_syncContactName);
    _phoneCtrl.removeListener(_syncContactPhone);
    _nameCtrl.dispose();
    _tradeNameCtrl.dispose();
    _documentCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _notesCtrl.dispose();
    _contactNameCtrl.dispose();
    _contactPhoneCtrl.dispose();
    _contactEmailCtrl.dispose();
    _cepCtrl.dispose();
    _streetCtrl.dispose();
    _numberCtrl.dispose();
    _complementCtrl.dispose();
    _districtCtrl.dispose();
    _cityCtrl.dispose();
    _referenceCtrl.dispose();
    super.dispose();
  }

  void _syncContactName() {
    if (_isEdit || _contactNameEdited) return;
    _contactNameCtrl.text = _nameCtrl.text;
  }

  void _syncContactPhone() {
    if (_isEdit || _contactPhoneEdited) return;
    _contactPhoneCtrl.text = _phoneCtrl.text;
  }

  bool get _hasAnyAddressInput =>
      _digitsOnly(_cepCtrl.text).isNotEmpty ||
      _streetCtrl.text.trim().isNotEmpty ||
      _numberCtrl.text.trim().isNotEmpty ||
      _complementCtrl.text.trim().isNotEmpty ||
      _districtCtrl.text.trim().isNotEmpty ||
      _cityCtrl.text.trim().isNotEmpty ||
      _referenceCtrl.text.trim().isNotEmpty;

  String? _validateDocument(String? v) {
    if (v == null || v.isEmpty) return null; // CPF/CNPJ opcional
    return _type.usesCpf ? validateCpf(v) : validateCnpj(v);
  }

  String? _validateAddressField(String? value, String label) {
    if (!_isEdit || _hasAnyAddressInput) {
      return validateRequired(value, label);
    }
    return null;
  }

  String? _validateAddressCep(String? value) {
    if (!_isEdit || _hasAnyAddressInput) {
      return validateCep(value);
    }
    return null;
  }

  String _digitsOnly(String value) => value.replaceAll(RegExp(r'\D'), '');

  String _formatCep(String value) {
    final digits = _digitsOnly(value);
    if (digits.length <= 5) return digits;
    return '${digits.substring(0, 5)}-${digits.substring(5)}';
  }

  String _formatCpf(String value) {
    final digits = _digitsOnly(value);
    if (digits.length <= 3) return digits;
    if (digits.length <= 6) {
      return '${digits.substring(0, 3)}.${digits.substring(3)}';
    }
    if (digits.length <= 9) {
      return '${digits.substring(0, 3)}.${digits.substring(3, 6)}.${digits.substring(6)}';
    }
    return '${digits.substring(0, 3)}.${digits.substring(3, 6)}.${digits.substring(6, 9)}-${digits.substring(9)}';
  }

  String _formatCnpj(String value) {
    final digits = _digitsOnly(value);
    if (digits.length <= 2) return digits;
    if (digits.length <= 5) {
      return '${digits.substring(0, 2)}.${digits.substring(2)}';
    }
    if (digits.length <= 8) {
      return '${digits.substring(0, 2)}.${digits.substring(2, 5)}.${digits.substring(5)}';
    }
    if (digits.length <= 12) {
      return '${digits.substring(0, 2)}.${digits.substring(2, 5)}.${digits.substring(5, 8)}/${digits.substring(8)}';
    }
    return '${digits.substring(0, 2)}.${digits.substring(2, 5)}.${digits.substring(5, 8)}/${digits.substring(8, 12)}-${digits.substring(12)}';
  }

  String _formatPhone(String value) {
    final digits = _digitsOnly(value);
    if (digits.isEmpty) return '';
    if (digits.length <= 2) return '($digits';

    final prefix = '(${digits.substring(0, 2)}) ';
    final number = digits.substring(2);
    if (number.length <= 4) return '$prefix$number';

    final split = digits.length <= 10 ? 4 : 5;
    if (number.length <= split) return '$prefix$number';
    return '$prefix${number.substring(0, split)}-${number.substring(split)}';
  }

  Future<void> _lookupCep() async {
    final cep = _digitsOnly(_cepCtrl.text);
    if (cep.length != 8 || cep == _lastCepLookup || _isCepLoading) return;

    setState(() {
      _isCepLoading = true;
      _lastCepLookup = cep;
    });

    try {
      // A consulta vive em core/location: o cadastro de fornecedor usa a
      // mesma, e duas cópias divergiriam no tratamento de erro.
      final address = await lookupCep(cep);
      if (!mounted) return;
      setState(() {
        if (address.street.isNotEmpty) _streetCtrl.text = address.street;
        if (address.district.isNotEmpty) _districtCtrl.text = address.district;
        if (address.city.isNotEmpty) _cityCtrl.text = address.city;
        if (kBrazilianStates.contains(address.state)) _stateUf = address.state;
      });
    } on CepLookupException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(e.message)),
      );
    } finally {
      if (mounted) setState(() => _isCepLoading = false);
    }
  }

  Future<void> _lookupAddressCoordinates() async {
    final requiredFields = [
      _streetCtrl.text,
      _numberCtrl.text,
      _cityCtrl.text,
      _stateUf,
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
        state: _stateUf,
        cep: _cepCtrl.text,
      );
      if (!mounted) return;
      setState(() {
        _addressLatitude = coordinates.latitude;
        _addressLongitude = coordinates.longitude;
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

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final notifier = ref.read(customerFormProvider.notifier);
    if (_isEdit) {
      final defaultAddress = ref
          .read(customerAddressesProvider(widget.customer!.id))
          .maybeWhen(
            data: (addresses) => addresses.cast<CustomerAddress?>().firstWhere(
                  (address) => address?.isDefault == true,
                  orElse: () => addresses.isNotEmpty ? addresses.first : null,
                ),
            orElse: () => null,
          );
      notifier.updateCustomer(
        original: widget.customer!,
        type: _type,
        name: _nameCtrl.text,
        tradeName: _tradeNameCtrl.text,
        document: _documentCtrl.text,
        email: _emailCtrl.text,
        phone: _phoneCtrl.text,
        notes: _notesCtrl.text,
        existingAddress: defaultAddress,
        addressCep: _cepCtrl.text,
        addressStreet: _streetCtrl.text,
        addressNumber: _numberCtrl.text,
        addressComplement: _complementCtrl.text,
        addressDistrict: _districtCtrl.text,
        addressCity: _cityCtrl.text,
        addressState: _stateUf,
        addressReference: _referenceCtrl.text,
        addressLatitude: _addressLatitude,
        addressLongitude: _addressLongitude,
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
        contactName: _contactNameCtrl.text,
        contactPhone: _contactPhoneCtrl.text,
        contactEmail: _contactEmailCtrl.text,
        addressCep: _cepCtrl.text,
        addressStreet: _streetCtrl.text,
        addressNumber: _numberCtrl.text,
        addressComplement: _complementCtrl.text,
        addressDistrict: _districtCtrl.text,
        addressCity: _cityCtrl.text,
        addressState: _stateUf,
        addressReference: _referenceCtrl.text,
        addressLatitude: _addressLatitude,
        addressLongitude: _addressLongitude,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final formState = ref.watch(customerFormProvider);
    final isLoading = formState is CustomerFormLoading;
    final existingAddresses = _isEdit
        ? ref.watch(customerAddressesProvider(widget.customer!.id))
        : const AsyncData<List<CustomerAddress>>([]);

    if (_isEdit && !_didLoadExistingAddress) {
      existingAddresses.whenData((addresses) {
        if (_didLoadExistingAddress) return;
        _didLoadExistingAddress = true;
        if (addresses.isEmpty) return;
        final address = addresses.firstWhere(
          (item) => item.isDefault,
          orElse: () => addresses.first,
        );
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() {
            _cepCtrl.text = _formatCep(address.cep);
            _streetCtrl.text = address.street;
            _numberCtrl.text = address.number;
            _complementCtrl.text = address.complement ?? '';
            _districtCtrl.text = address.district;
            _cityCtrl.text = address.city;
            _referenceCtrl.text = address.reference ?? '';
            _stateUf = address.state;
            _addressLatitude = address.latitude;
            _addressLongitude = address.longitude;
          });
        });
      });
    }

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
        if (widget.embedded) {
          Navigator.of(context).pop(
            next.isCreate && widget.returnCreatedCustomerOnCreate
                ? next.customer
                : true,
          );
        } else {
          context.pop();
        }
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

    final form = SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppFormSection(
              title: 'Identificação',
              icon: Icons.badge_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SegmentedButton<CustomerType>(
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
                                _documentCtrl.clear();
                              });
                            },
                      multiSelectionEnabled: false,
                    ),
                  ),
                  const SizedBox(height: 14),
                  AppFormGrid(
                    children: [
                      AppFormFieldSpan(
                        widthFactor: 1.2,
                        child: TextFormField(
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
                      ),
                      if (!_type.usesCpf)
                        TextFormField(
                          controller: _tradeNameCtrl,
                          textCapitalization: TextCapitalization.words,
                          decoration:
                              const InputDecoration(labelText: 'Nome fantasia'),
                          enabled: !isLoading,
                        ),
                      AppFormFieldSpan(
                        widthFactor: 1.2,
                        child: TextFormField(
                          controller: _documentCtrl,
                          decoration: InputDecoration(
                            labelText: _type.usesCpf ? 'CPF' : 'CNPJ',
                            hintText: _type.usesCpf
                                ? '000.000.000-00'
                                : '00.000.000/0000-00',
                          ),
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            _DigitsMaskTextInputFormatter(
                              maxDigits: _type.usesCpf ? 11 : 14,
                              formatter:
                                  _type.usesCpf ? _formatCpf : _formatCnpj,
                            ),
                          ],
                          validator: _validateDocument,
                          enabled: !isLoading,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppFormSection(
              title: 'Contato',
              icon: Icons.contact_phone_outlined,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  const spacing = 14.0;
                  final useStackedLayout = constraints.maxWidth < 520;
                  final baseWidth = (constraints.maxWidth - spacing) / 2;
                  final emailWidth = baseWidth * 1.2;
                  final phoneWidth =
                      constraints.maxWidth - spacing - emailWidth;

                  final emailField = TextFormField(
                    controller: _emailCtrl,
                    decoration: const InputDecoration(labelText: 'E-mail'),
                    keyboardType: TextInputType.emailAddress,
                    autocorrect: false,
                    validator: (v) =>
                        v != null && v.isNotEmpty ? validateEmail(v) : null,
                    enabled: !isLoading,
                  );
                  final phoneField = TextFormField(
                    controller: _phoneCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Telefone',
                      hintText: '(11) 99999-9999',
                    ),
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      _DigitsMaskTextInputFormatter(
                        maxDigits: 11,
                        formatter: _formatPhone,
                      ),
                    ],
                    validator: validatePhone,
                    enabled: !isLoading,
                  );

                  if (useStackedLayout) {
                    return Column(
                      children: [
                        emailField,
                        const SizedBox(height: spacing),
                        phoneField,
                      ],
                    );
                  }

                  return Row(
                    children: [
                      SizedBox(width: emailWidth, child: emailField),
                      const SizedBox(width: spacing),
                      SizedBox(width: phoneWidth, child: phoneField),
                    ],
                  );
                },
              ),
            ),
            if (!_isEdit) ...[
              const SizedBox(height: 16),
              AppFormSection(
                title: 'Pessoa de contato',
                icon: Icons.supervisor_account_outlined,
                child: AppFormGrid(
                  children: [
                    AppFormFieldSpan(
                      widthFactor: 1.2,
                      child: TextFormField(
                        controller: _contactNameCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(
                          labelText: 'Pessoa de contato *',
                          hintText: 'Pode ser o mesmo nome do cliente',
                        ),
                        validator: (v) =>
                            validateRequired(v, 'Pessoa de contato'),
                        onChanged: (_) => _contactNameEdited = true,
                        enabled: !isLoading,
                      ),
                    ),
                    AppFormFieldSpan(
                      widthFactor: 1.2,
                      child: TextFormField(
                        controller: _contactPhoneCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Telefone do contato',
                          hintText: '(11) 99999-9999',
                        ),
                        keyboardType: TextInputType.phone,
                        inputFormatters: [
                          _DigitsMaskTextInputFormatter(
                            maxDigits: 11,
                            formatter: _formatPhone,
                          ),
                        ],
                        validator: validatePhone,
                        onChanged: (_) => _contactPhoneEdited = true,
                        enabled: !isLoading,
                      ),
                    ),
                    AppFormFieldSpan(
                      widthFactor: 1.2,
                      child: TextFormField(
                        controller: _contactEmailCtrl,
                        decoration: const InputDecoration(
                            labelText: 'E-mail do contato'),
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        validator: (v) => v != null && v.isNotEmpty
                            ? validateEmail(v)
                            : null,
                        enabled: !isLoading,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 16),
            AppFormSection(
              title: _isEdit ? 'Endereço principal' : 'Endereço padrão',
              icon: Icons.location_on_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_isEdit)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 14),
                      child: existingAddresses.when(
                        loading: () => const Text(
                          'Carregando endereço atual...',
                        ),
                        error: (_, __) => const Text(
                          'Não foi possível carregar o endereço atual. Você ainda pode preencher manualmente.',
                        ),
                        data: (addresses) => Text(
                          addresses.isEmpty
                              ? 'Nenhum endereço cadastrado ainda. Se o endereço estiver em Observações, copie e cole nos campos abaixo.'
                              : 'Edite o endereço principal abaixo. Se algo veio em Observações, copie e cole nos campos corretos.',
                        ),
                      ),
                    ),
                  AppFormGrid(
                    children: [
                      TextFormField(
                        controller: _cepCtrl,
                        decoration: InputDecoration(
                          labelText: _isEdit ? 'CEP' : 'CEP *',
                          hintText: '00000-000',
                          suffixIcon: _isCepLoading
                              ? const Padding(
                                  padding: EdgeInsets.all(14),
                                  child: SizedBox(
                                    height: 18,
                                    width: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.4,
                                    ),
                                  ),
                                )
                              : IconButton(
                                  tooltip: 'Buscar CEP',
                                  onPressed: isLoading ? null : _lookupCep,
                                  icon: const Icon(Icons.search_outlined),
                                ),
                        ),
                        keyboardType: TextInputType.number,
                        validator: _validateAddressCep,
                        onChanged: (value) {
                          final formatted = _formatCep(value);
                          if (formatted != value) {
                            _cepCtrl.value = TextEditingValue(
                              text: formatted,
                              selection: TextSelection.collapsed(
                                offset: formatted.length,
                              ),
                            );
                          }
                          _lookupCep();
                        },
                        enabled: !isLoading,
                      ),
                      AppFormFieldSpan(
                        widthFactor: 1.2,
                        child: TextFormField(
                          controller: _streetCtrl,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: _isEdit
                                ? 'Rua / Avenida'
                                : 'Rua / Avenida *',
                          ),
                          validator: (v) =>
                              _validateAddressField(v, 'Rua / Avenida'),
                          enabled: !isLoading,
                        ),
                      ),
                      TextFormField(
                        controller: _numberCtrl,
                        decoration: InputDecoration(
                          labelText: _isEdit ? 'Número' : 'Número *',
                        ),
                        validator: (v) => _validateAddressField(v, 'Número'),
                        enabled: !isLoading,
                      ),
                      TextFormField(
                        controller: _complementCtrl,
                        textCapitalization: TextCapitalization.words,
                        decoration:
                            const InputDecoration(labelText: 'Complemento'),
                        enabled: !isLoading,
                      ),
                      AppFormFieldSpan(
                        widthFactor: 1.2,
                        child: TextFormField(
                          controller: _districtCtrl,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: _isEdit ? 'Bairro' : 'Bairro *',
                          ),
                          validator: (v) =>
                              _validateAddressField(v, 'Bairro'),
                          enabled: !isLoading,
                        ),
                      ),
                      AppFormFieldSpan(
                        widthFactor: 1.2,
                        child: TextFormField(
                          controller: _cityCtrl,
                          textCapitalization: TextCapitalization.words,
                          decoration: InputDecoration(
                            labelText: _isEdit ? 'Cidade' : 'Cidade *',
                          ),
                          validator: (v) =>
                              _validateAddressField(v, 'Cidade'),
                          enabled: !isLoading,
                        ),
                      ),
                      DropdownButtonFormField<String>(
                        initialValue: _stateUf,
                        isExpanded: true,
                        decoration: InputDecoration(
                          labelText: _isEdit ? 'UF' : 'UF *',
                        ),
                        items: kBrazilianStates
                            .map(
                              (uf) => DropdownMenuItem(
                                value: uf,
                                child: Text(uf),
                              ),
                            )
                            .toList(),
                        onChanged: isLoading
                            ? null
                            : (value) => setState(() {
                                  if (value != null) _stateUf = value;
                                }),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _referenceCtrl,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      labelText: 'Referência',
                      alignLabelWithHint: true,
                    ),
                    maxLines: 2,
                    enabled: !isLoading,
                  ),
                  const SizedBox(height: 14),
                  AddressLocationBox(
                    latitude: _addressLatitude,
                    longitude: _addressLongitude,
                    isLoading: _isGeocoding,
                    onLocate: isLoading || _isGeocoding
                        ? null
                        : _lookupAddressCoordinates,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            AppFormSection(
              title: 'Extras',
              icon: Icons.notes_outlined,
              child: TextFormField(
                controller: _notesCtrl,
                decoration: const InputDecoration(
                  labelText: 'Observações internas',
                  alignLabelWithHint: true,
                ),
                maxLines: 3,
                enabled: !isLoading,
              ),
            ),
          ],
        ),
      ),
    );

    final actionLabel = _isEdit ? 'Salvar alterações' : 'Cadastrar cliente';
    final actionButton = ElevatedButton(
      onPressed: isLoading ? null : _submit,
      child: isLoading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(strokeWidth: 2.5),
            )
          : Text(actionLabel),
    );

    if (widget.embedded) {
      // Diálogo (showAppFormDialog) já traz título e botão de fechar — só
      // falta o botão de ação fixo embaixo do conteúdo rolável.
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(child: form),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: actionButton,
          ),
        ],
      );
    }

    return AppFormScaffold(
      title: _isEdit ? 'Editar cliente' : 'Novo cliente',
      body: form,
      actionLabel: actionLabel,
      onAction: isLoading ? null : _submit,
      actionLoading: isLoading,
    );
  }
}

class _DigitsMaskTextInputFormatter extends TextInputFormatter {
  const _DigitsMaskTextInputFormatter({
    required this.maxDigits,
    required this.formatter,
  });

  final int maxDigits;
  final String Function(String value) formatter;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final limitedDigits =
        digits.length > maxDigits ? digits.substring(0, maxDigits) : digits;
    final masked = formatter(limitedDigits);
    return TextEditingValue(
      text: masked,
      selection: TextSelection.collapsed(offset: masked.length),
    );
  }
}

import 'package:flutter/material.dart';

import '../../domain/customer.dart';
import '../../domain/customer_search.dart';

/// Campo de cliente com busca no próprio campo: nome, CPF/CNPJ ou telefone.
/// Substitui o dropdown, que obrigava a rolar a lista inteira.
class CustomerSearchField extends StatelessWidget {
  const CustomerSearchField({
    super.key,
    required this.customers,
    required this.selected,
    required this.onChanged,
    this.enabled = true,
    this.label = 'Cliente',
    this.validator,
  });

  final List<Customer> customers;
  final Customer? selected;
  final ValueChanged<Customer?> onChanged;
  final bool enabled;
  final String label;
  final String? Function(Customer?)? validator;

  @override
  Widget build(BuildContext context) {
    return FormField<Customer>(
      initialValue: selected,
      validator: (_) => validator?.call(selected),
      builder: (field) {
        return Autocomplete<Customer>(
          displayStringForOption: (customer) => customer.name,
          initialValue: TextEditingValue(text: selected?.name ?? ''),
          optionsBuilder: (value) => customers
              .where((customer) => customerMatchesQuery(customer, value.text))
              .take(12),
          onSelected: enabled
              ? (customer) {
                  field.didChange(customer);
                  onChanged(customer);
                }
              : null,
          fieldViewBuilder: (context, controller, focusNode, onSubmitted) {
            return TextField(
              controller: controller,
              focusNode: focusNode,
              enabled: enabled,
              decoration: InputDecoration(
                labelText: label,
                hintText: 'Buscar por nome, CPF/CNPJ ou telefone',
                errorText: field.errorText,
                suffixIcon: const Icon(Icons.search_outlined),
              ),
              // Digitar depois de escolher desfaz a seleção: senão o campo
              // mostraria um nome e o formulário guardaria outro cliente.
              onChanged: (_) {
                if (field.value != null) {
                  field.didChange(null);
                  onChanged(null);
                }
              },
            );
          },
          optionsViewBuilder: (context, onSelected, options) {
            final theme = Theme.of(context);
            return Align(
              alignment: Alignment.topLeft,
              child: Material(
                elevation: 12,
                borderRadius: BorderRadius.circular(20),
                color: theme.colorScheme.surface,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxHeight: 320,
                    maxWidth: 420,
                  ),
                  child: ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    shrinkWrap: true,
                    itemCount: options.length,
                    separatorBuilder: (_, __) => const Divider(height: 1),
                    itemBuilder: (context, index) {
                      final customer = options.elementAt(index);
                      return ListTile(
                        dense: true,
                        leading: CircleAvatar(
                          child: Text(customer.name[0].toUpperCase()),
                        ),
                        title: Text(
                          customer.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          customerSearchSubtitle(customer),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        onTap: () => onSelected(customer),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

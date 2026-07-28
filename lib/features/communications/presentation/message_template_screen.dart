import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/app_form_dialog.dart';
import '../../../core/widgets/app_form_layout.dart';
import '../../../core/widgets/error_view.dart';
import '../../../core/widgets/neomorphic.dart';
import '../application/communication_notifier.dart';
import '../domain/message_template.dart';

// ── Tela de gerenciamento de templates ────────────────────────────────────────

class MessageTemplateScreen extends ConsumerWidget {
  const MessageTemplateScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final templatesAsync = ref.watch(messageTemplatesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Templates de mensagem'),
        actions: [
          IconButton(
            tooltip: 'Atualizar',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(messageTemplatesProvider),
          ),
          IconButton(
            tooltip: 'Novo template',
            icon: const Icon(Icons.add),
            onPressed: () => _openForm(context, ref, null),
          ),
        ],
      ),
      body: templatesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorView(
          message: e.toString(),
          onRetry: () => ref.invalidate(messageTemplatesProvider),
        ),
        data: (templates) {
          if (templates.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.chat_bubble_outline,
                      size: 48, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(height: 12),
                  Text(
                    'Nenhum template cadastrado.',
                    style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    icon: const Icon(Icons.add),
                    label: const Text('Criar primeiro template'),
                    onPressed: () => _openForm(context, ref, null),
                  ),
                ],
              ),
            );
          }

          final byChannel = <MessageChannel, List<MessageTemplate>>{};
          for (final t in templates) {
            byChannel.putIfAbsent(t.channel, () => []).add(t);
          }

          return ListView(
            padding: const EdgeInsets.all(16),
            children: byChannel.entries.map((entry) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Icon(_channelIcon(entry.key),
                            size: 18,
                            color: _channelColor(entry.key, theme)),
                        const SizedBox(width: 8),
                        Text(
                          entry.key.label,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: _channelColor(entry.key, theme),
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...entry.value.map((t) => Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _TemplateCard(
                          template: t,
                          onEdit: () => _openForm(context, ref, t),
                          onToggle: () => _toggleActive(ref, t),
                          onDelete: () => _confirmDelete(context, ref, t),
                        ),
                      )),
                  const SizedBox(height: 8),
                ],
              );
            }).toList(),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Novo template'),
        onPressed: () => _openForm(context, ref, null),
      ),
    );
  }

  Future<void> _openForm(
      BuildContext context, WidgetRef ref, MessageTemplate? existing) async {
    await showAppFormDialog<void>(
      context: context,
      title: existing == null ? 'Novo template' : 'Editar template',
      maxWidth: 600,
      child: _TemplateForm(existing: existing),
    );
    ref.invalidate(messageTemplatesProvider);
  }

  Future<void> _toggleActive(WidgetRef ref, MessageTemplate t) async {
    await ref
        .read(communicationRepositoryProvider)
        .updateTemplate(t.id, isActive: !t.isActive);
    ref.invalidate(messageTemplatesProvider);
  }

  Future<void> _confirmDelete(
      BuildContext context, WidgetRef ref, MessageTemplate t) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Excluir template?'),
        content: Text('Tem certeza que deseja excluir "${t.name}"?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
            style:
                FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (confirm == true) {
      await ref
          .read(communicationRepositoryProvider)
          .deleteTemplate(t.id);
      ref.invalidate(messageTemplatesProvider);
    }
  }

  IconData _channelIcon(MessageChannel c) => switch (c) {
        MessageChannel.whatsapp => Icons.chat_bubble_outline,
        MessageChannel.email => Icons.email_outlined,
        MessageChannel.phone => Icons.phone_outlined,
        MessageChannel.generic => Icons.message_outlined,
      };

  Color _channelColor(MessageChannel c, ThemeData theme) => switch (c) {
        MessageChannel.whatsapp => Colors.green.shade700,
        MessageChannel.email => Colors.blue.shade700,
        MessageChannel.phone => Colors.orange.shade700,
        MessageChannel.generic => theme.colorScheme.secondary,
      };
}

// ── Card de template ──────────────────────────────────────────────────────────

class _TemplateCard extends StatelessWidget {
  const _TemplateCard({
    required this.template,
    required this.onEdit,
    required this.onToggle,
    required this.onDelete,
  });

  final MessageTemplate template;
  final VoidCallback onEdit;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return NeomorphicPanel(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  template.name,
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
              ),
              if (!template.isActive)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text('Inativo',
                      style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant)),
                ),
              const SizedBox(width: 4),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert, size: 18),
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'toggle') onToggle();
                  if (v == 'delete') onDelete();
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'edit', child: Text('Editar')),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(
                        template.isActive ? 'Desativar' : 'Ativar'),
                  ),
                  const PopupMenuDivider(),
                  const PopupMenuItem(
                    value: 'delete',
                    child: Text('Excluir',
                        style: TextStyle(color: Colors.red)),
                  ),
                ],
              ),
            ],
          ),
          if (template.subject != null) ...[
            const SizedBox(height: 4),
            Text(
              'Assunto: ${template.subject}',
              style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            template.body.length > 120
                ? '${template.body.substring(0, 120)}…'
                : template.body,
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}

// ── Formulário de template ────────────────────────────────────────────────────

class _TemplateForm extends ConsumerStatefulWidget {
  const _TemplateForm({this.existing});

  final MessageTemplate? existing;

  @override
  ConsumerState<_TemplateForm> createState() => _TemplateFormState();
}

class _TemplateFormState extends ConsumerState<_TemplateForm> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController =
      TextEditingController(text: widget.existing?.name ?? '');
  late final _subjectController =
      TextEditingController(text: widget.existing?.subject ?? '');
  late final _bodyController =
      TextEditingController(text: widget.existing?.body ?? '');
  late MessageChannel _channel =
      widget.existing?.channel ?? MessageChannel.whatsapp;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _nameController.dispose();
    _subjectController.dispose();
    _bodyController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final repo = ref.read(communicationRepositoryProvider);
      if (widget.existing == null) {
        await repo.createTemplate(
          name: _nameController.text.trim(),
          channel: _channel,
          body: _bodyController.text.trim(),
          subject: _subjectController.text.trim().isNotEmpty
              ? _subjectController.text.trim()
              : null,
        );
      } else {
        await repo.updateTemplate(
          widget.existing!.id,
          name: _nameController.text.trim(),
          body: _bodyController.text.trim(),
          subject: _subjectController.text.trim().isNotEmpty
              ? _subjectController.text.trim()
              : null,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppFormSection(
            title: 'Informações do template',
            icon: Icons.message_outlined,
            child: AppFormGrid(
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Nome do template *',
                    hintText: 'ex.: Confirmação de OS',
                  ),
                  validator: (v) =>
                      (v?.trim().isEmpty ?? true) ? 'Informe um nome.' : null,
                ),
                DropdownButtonFormField<MessageChannel>(
                  isExpanded: true,
                  initialValue: _channel,
                  decoration: const InputDecoration(labelText: 'Canal *'),
                  items: [
                    MessageChannel.whatsapp,
                    MessageChannel.email,
                    MessageChannel.generic,
                  ]
                      .map((c) => DropdownMenuItem(
                            value: c,
                            child: Text(c.label),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _channel = v);
                  },
                ),
                if (_channel == MessageChannel.email)
                  TextFormField(
                    controller: _subjectController,
                    decoration: const InputDecoration(
                      labelText: 'Assunto',
                      hintText: 'Assunto do e-mail (opcional)',
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          AppFormSection(
            title: 'Corpo da mensagem',
            icon: Icons.text_fields_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _bodyController,
                  minLines: 5,
                  maxLines: 12,
                  maxLength: 2000,
                  decoration: const InputDecoration(
                    hintText:
                        'Use {{customer_name}}, {{company_name}}, {{quotation_number}}, {{work_order_number}}, {{amount}}, {{link}}…',
                    border: OutlineInputBorder(),
                    alignLabelWithHint: true,
                  ),
                  validator: (v) =>
                      (v?.trim().isEmpty ?? true) ? 'Escreva a mensagem.' : null,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: TemplateVars.all
                      .map((v) => ActionChip(
                            label: Text('{{$v}}'),
                            visualDensity: VisualDensity.compact,
                            onPressed: () {
                              final pos = _bodyController.selection.base.offset;
                              final text = _bodyController.text;
                              final insert = '{{$v}}';
                              if (pos >= 0 && pos <= text.length) {
                                _bodyController.text = text.substring(0, pos) +
                                    insert +
                                    text.substring(pos);
                                _bodyController.selection =
                                    TextSelection.fromPosition(
                                  TextPosition(offset: pos + insert.length),
                                );
                              } else {
                                _bodyController.text += insert;
                              }
                            },
                          ))
                      .toList(),
                ),
              ],
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error)),
          ],
          const SizedBox(height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancelar'),
              ),
              const SizedBox(width: 12),
              FilledButton(
                onPressed: _saving ? null : _save,
                child: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child:
                            CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(widget.existing == null ? 'Criar' : 'Salvar'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

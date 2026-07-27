import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../application/communication_notifier.dart';
import '../domain/message_template.dart';

/// Contexto passado para preencher as variáveis do template.
class MessageContext {
  const MessageContext({
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.customerEmail,
    required this.companyName,
    this.quotationNumber,
    this.workOrderNumber,
    this.serviceTitle,
    this.amount,
    this.publicLink,
    this.relatedEntity,
    this.relatedEntityId,
  });

  final String customerId;
  final String customerName;
  final String customerPhone;
  final String customerEmail;
  final String companyName;
  final String? quotationNumber;
  final String? workOrderNumber;
  final String? serviceTitle;
  final String? amount;
  final String? publicLink;
  final String? relatedEntity;
  final String? relatedEntityId;

  Map<String, String> toVars() => {
        TemplateVars.customerName: customerName,
        TemplateVars.companyName: companyName,
        if (quotationNumber != null)
          TemplateVars.quotationNumber: quotationNumber!,
        if (workOrderNumber != null)
          TemplateVars.workOrderNumber: workOrderNumber!,
        if (serviceTitle != null) TemplateVars.serviceTitle: serviceTitle!,
        if (amount != null) TemplateVars.amount: amount!,
        if (publicLink != null) TemplateVars.link: publicLink!,
      };
}

// ── Abertura do painel ────────────────────────────────────────────────────────

/// Abre o painel de envio de mensagem sem depender do botão.
///
/// Útil quando a tela precisa preparar algo antes (por exemplo, gerar um link
/// público) e só então oferecer o envio.
Future<void> showSendMessageSheet(
  BuildContext context,
  MessageContext messageContext,
) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => _SendMessageSheet(messageContext: messageContext),
  );
}

class SendMessageButton extends StatelessWidget {
  const SendMessageButton({
    super.key,
    required this.messageContext,
    this.label = 'Enviar mensagem',
  });

  final MessageContext messageContext;
  final String label;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: const Icon(Icons.send_outlined, size: 18),
      label: Text(label),
      onPressed: () => showSendMessageSheet(context, messageContext),
    );
  }
}

// ── Painel (bottom sheet) ─────────────────────────────────────────────────────

class _SendMessageSheet extends ConsumerStatefulWidget {
  const _SendMessageSheet({required this.messageContext});

  final MessageContext messageContext;

  @override
  ConsumerState<_SendMessageSheet> createState() => _SendMessageSheetState();
}

class _SendMessageSheetState extends ConsumerState<_SendMessageSheet> {
  MessageTemplate? _selected;
  final _bodyController = TextEditingController();
  final _subjectController = TextEditingController();
  MessageChannel _channel = MessageChannel.whatsapp;
  bool _sending = false;
  String? _error;

  @override
  void dispose() {
    _bodyController.dispose();
    _subjectController.dispose();
    super.dispose();
  }

  void _applyTemplate(MessageTemplate tpl) {
    final vars = widget.messageContext.toVars();
    setState(() {
      _selected = tpl;
      _channel = tpl.channel;
      _bodyController.text = tpl.resolveBody(vars);
      _subjectController.text = tpl.resolveSubject(vars) ?? '';
    });
  }

  Future<void> _send() async {
    final body = _bodyController.text.trim();
    if (body.isEmpty) {
      setState(() => _error = 'Escreva a mensagem antes de enviar.');
      return;
    }

    setState(() {
      _sending = true;
      _error = null;
    });

    try {
      await _openChannel(body);
      if (!mounted) return;

      // Loga a comunicação
      await ref.read(communicationRepositoryProvider).logCommunication(
            customerId: widget.messageContext.customerId,
            channel: _channel,
            bodyPreview: body.length > 500 ? body.substring(0, 500) : body,
            subject: _subjectController.text.trim().isNotEmpty
                ? _subjectController.text.trim()
                : null,
            relatedEntity: widget.messageContext.relatedEntity,
            relatedEntityId: widget.messageContext.relatedEntityId,
            templateId: _selected?.id,
          );

      // Invalida providers de log
      ref.invalidate(customerCommunicationLogsProvider);
      ref.invalidate(entityCommunicationLogsProvider);

      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _openChannel(String body) async {
    switch (_channel) {
      case MessageChannel.whatsapp:
        final phone = widget.messageContext.customerPhone
            .replaceAll(RegExp(r'\D'), '');
        final encoded = Uri.encodeComponent(body);
        final uri = Uri.parse('https://wa.me/55$phone?text=$encoded');
        if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
          // Fallback: copia para área de transferência
          await Clipboard.setData(ClipboardData(text: body));
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'WhatsApp não encontrado — mensagem copiada para a área de transferência.'),
              ),
            );
          }
        }
      case MessageChannel.email:
        final subject = Uri.encodeComponent(_subjectController.text.trim());
        final bodyEncoded = Uri.encodeComponent(body);
        final email = widget.messageContext.customerEmail;
        final uri = Uri.parse('mailto:$email?subject=$subject&body=$bodyEncoded');
        if (!await launchUrl(uri)) {
          await Clipboard.setData(ClipboardData(text: body));
        }
      case MessageChannel.generic:
      case MessageChannel.phone:
        // Apenas copia o texto
        await Clipboard.setData(ClipboardData(text: body));
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Mensagem copiada para a área de transferência.')),
          );
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final templatesAsync = ref.watch(messageTemplatesProvider);

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => Column(
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text('Enviar mensagem',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              children: [
                // Canal
                Text('Canal', style: theme.textTheme.labelMedium),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    MessageChannel.whatsapp,
                    MessageChannel.email,
                    MessageChannel.generic,
                  ]
                      .map((c) => ChoiceChip(
                            label: Text(c.label),
                            selected: _channel == c,
                            onSelected: (_) =>
                                setState(() => _channel = c),
                          ))
                      .toList(),
                ),
                const SizedBox(height: 16),
                // Templates
                Text('Templates', style: theme.textTheme.labelMedium),
                const SizedBox(height: 6),
                templatesAsync.when(
                  loading: () =>
                      const Center(child: CircularProgressIndicator()),
                  error: (_, __) => const Text('Erro ao carregar templates'),
                  data: (templates) {
                    final filtered = templates
                        .where((t) =>
                            t.channel == _channel ||
                            t.channel == MessageChannel.generic)
                        .toList();
                    if (filtered.isEmpty) {
                      return Text(
                        'Nenhum template para este canal.',
                        style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant),
                      );
                    }
                    return Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: filtered
                          .map((t) => ActionChip(
                                label: Text(t.name),
                                onPressed: () => _applyTemplate(t),
                                backgroundColor: _selected?.id == t.id
                                    ? theme.colorScheme.primaryContainer
                                    : null,
                              ))
                          .toList(),
                    );
                  },
                ),
                const SizedBox(height: 16),
                // Assunto (email)
                if (_channel == MessageChannel.email) ...[
                  Text('Assunto', style: theme.textTheme.labelMedium),
                  const SizedBox(height: 6),
                  TextField(
                    controller: _subjectController,
                    decoration: const InputDecoration(
                      hintText: 'Assunto do e-mail',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                // Corpo
                Text('Mensagem', style: theme.textTheme.labelMedium),
                const SizedBox(height: 6),
                TextField(
                  controller: _bodyController,
                  minLines: 5,
                  maxLines: 12,
                  maxLength: 2000,
                  decoration: InputDecoration(
                    hintText: 'Digite ou selecione um template acima…',
                    border: const OutlineInputBorder(),
                    counterStyle: theme.textTheme.bodySmall,
                  ),
                ),
                if (_error != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    _error!,
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                ],
                const SizedBox(height: 16),
                // Botões
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.copy_outlined, size: 18),
                        label: const Text('Só copiar'),
                        onPressed: _sending
                            ? null
                            : () async {
                                final body = _bodyController.text.trim();
                                if (body.isEmpty) return;
                                await Clipboard.setData(
                                    ClipboardData(text: body));
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(
                                        content:
                                            Text('Mensagem copiada.')),
                                  );
                                }
                              },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton.icon(
                        icon: _sending
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white),
                              )
                            : Icon(
                                _channel == MessageChannel.whatsapp
                                    ? Icons.chat_bubble_outline
                                    : _channel == MessageChannel.email
                                        ? Icons.email_outlined
                                        : Icons.send_outlined,
                                size: 18,
                              ),
                        label: Text(_channel == MessageChannel.whatsapp
                            ? 'Abrir WhatsApp'
                            : _channel == MessageChannel.email
                                ? 'Abrir e-mail'
                                : 'Enviar'),
                        onPressed: _sending ? null : _send,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

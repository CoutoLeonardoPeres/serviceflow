import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../files/stored_attachment.dart';
import 'neomorphic.dart';

class AttachmentGallery extends StatelessWidget {
  const AttachmentGallery({
    super.key,
    required this.title,
    required this.attachments,
    required this.onOpen,
    required this.onDownload,
    this.onPreview,
    this.thumbnailUrlBuilder,
    this.emptyMessage = 'Nenhum anexo disponível.',
  });

  final String title;
  final List<StoredAttachment> attachments;
  final Future<void> Function(StoredAttachment attachment) onOpen;
  final Future<void> Function(StoredAttachment attachment) onDownload;
  final Future<void> Function(StoredAttachment attachment)? onPreview;
  final Future<String?> Function(StoredAttachment attachment)?
      thumbnailUrlBuilder;
  final String emptyMessage;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('dd/MM/yyyy HH:mm');

    return NeomorphicPanel(
      borderRadius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.attach_file_outlined,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (attachments.isEmpty)
            Text(
              emptyMessage,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            )
          else
            Column(
              children: [
                for (final attachment in attachments) ...[
                  NeomorphicInset(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _AttachmentThumb(
                          attachment: attachment,
                          thumbnailUrlBuilder: thumbnailUrlBuilder,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                attachment.fileName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.titleSmall?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${attachment.typeLabel} · ${attachment.sizeLabel} · ${dateFormat.format(attachment.createdAt.toLocal())}',
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (onPreview != null &&
                            (attachment.isImage || attachment.isPdf))
                          IconButton(
                            tooltip: 'Visualizar',
                            onPressed: () => onPreview!(attachment),
                            icon: const Icon(Icons.visibility_outlined),
                          ),
                        IconButton(
                          tooltip: 'Abrir',
                          onPressed: () => onOpen(attachment),
                          icon: const Icon(Icons.open_in_new_outlined),
                        ),
                        IconButton(
                          tooltip: 'Baixar',
                          onPressed: () => onDownload(attachment),
                          icon: const Icon(Icons.download_outlined),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
        ],
      ),
    );
  }
}

class _AttachmentThumb extends StatelessWidget {
  const _AttachmentThumb({
    required this.attachment,
    required this.thumbnailUrlBuilder,
  });

  final StoredAttachment attachment;
  final Future<String?> Function(StoredAttachment attachment)?
      thumbnailUrlBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (attachment.isImage && thumbnailUrlBuilder != null) {
      return FutureBuilder<String?>(
        future: thumbnailUrlBuilder!(attachment),
        builder: (context, snapshot) {
          final url = snapshot.data;
          if (url != null && url.isNotEmpty) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Image.network(
                url,
                width: 58,
                height: 58,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _FallbackThumb(
                  icon: Icons.image_outlined,
                  color: theme.colorScheme.primary,
                ),
              ),
            );
          }
          return _FallbackThumb(
            icon: Icons.image_outlined,
            color: theme.colorScheme.primary,
          );
        },
      );
    }

    return _FallbackThumb(
      icon: attachmentIcon(attachment),
      color: theme.colorScheme.primary,
    );
  }
}

class _FallbackThumb extends StatelessWidget {
  const _FallbackThumb({
    required this.icon,
    required this.color,
  });

  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 58,
      height: 58,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: color),
    );
  }
}

IconData attachmentIcon(StoredAttachment attachment) {
  if (attachment.isImage) return Icons.image_outlined;
  if (attachment.isVideo) return Icons.videocam_outlined;
  if (attachment.isPdf) return Icons.picture_as_pdf_outlined;
  return Icons.description_outlined;
}

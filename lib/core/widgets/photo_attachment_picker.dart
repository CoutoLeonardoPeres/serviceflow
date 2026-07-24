import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../files/attachment_picker.dart';
import 'neomorphic.dart';

class SelectedPhotoAttachment {
  const SelectedPhotoAttachment(this.file);

  final PlatformFile file;

  String get name => file.name;
  int get size => file.size;
  Uint8List? get bytes => file.bytes;

  String get mimeType {
    final lower = name.toLowerCase();
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.mp4')) return 'video/mp4';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.doc')) return 'application/msword';
    if (lower.endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (lower.endsWith('.xls')) return 'application/vnd.ms-excel';
    if (lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.txt')) return 'text/plain';
    return 'application/octet-stream';
  }

  bool get isImage => mimeType.startsWith('image/');

  IconData get icon =>
      isImage ? Icons.image_outlined : Icons.description_outlined;
}

class PhotoAttachmentPicker extends StatefulWidget {
  const PhotoAttachmentPicker({
    super.key,
    required this.photos,
    required this.onChanged,
    this.enabled = true,
    this.title = 'Fotos de identificação',
    this.helper =
        'Use imagens do cliente, equipamento, local ou serviço para catálogo e histórico.',
    this.allowDocuments = false,
  });

  final List<SelectedPhotoAttachment> photos;
  final ValueChanged<List<SelectedPhotoAttachment>> onChanged;
  final bool enabled;
  final String title;
  final String helper;
  final bool allowDocuments;

  @override
  State<PhotoAttachmentPicker> createState() => _PhotoAttachmentPickerState();
}

class _PhotoAttachmentPickerState extends State<PhotoAttachmentPicker> {
  Future<void> _pickPhotos() async {
    try {
      final files = await pickAttachments(
        allowDocuments: widget.allowDocuments,
        allowMultiple: true,
      );
      if (!mounted || files == null || files.isEmpty) return;
      widget.onChanged([
        ...widget.photos,
        ...files.map(SelectedPhotoAttachment.new),
      ]);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${widget.allowDocuments ? 'Nao foi possivel abrir o seletor de arquivos.' : 'Nao foi possivel abrir o seletor de fotos.'} ${error.toString()}',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return NeomorphicInset(
      borderRadius: 20,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                Icons.photo_camera_outlined,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w900,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      widget.helper,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              OutlinedButton.icon(
                onPressed: widget.enabled ? () => _pickPhotos() : null,
                icon: Icon(
                  widget.allowDocuments
                      ? Icons.attach_file_outlined
                      : Icons.add_photo_alternate_outlined,
                ),
                label: Text(
                    widget.allowDocuments ? 'Adicionar arquivos' : 'Adicionar'),
              ),
            ],
          ),
          if (widget.photos.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final entry in widget.photos.indexed)
                  InputChip(
                    avatar: Icon(entry.$2.icon, size: 18),
                    label: Text(
                      '${entry.$2.name} · ${(entry.$2.size / 1024).toStringAsFixed(1)} KB',
                      overflow: TextOverflow.ellipsis,
                    ),
                    onDeleted: widget.enabled
                        ? () {
                            final next = [...widget.photos]..removeAt(entry.$1);
                            widget.onChanged(next);
                          }
                        : null,
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class StoredAttachment {
  const StoredAttachment({
    required this.id,
    required this.storagePath,
    required this.mimeType,
    required this.sizeBytes,
    required this.createdAt,
    this.kind,
  });

  final String id;
  final String storagePath;
  final String mimeType;
  final int sizeBytes;
  final DateTime createdAt;
  final String? kind;

  bool get isImage => mimeType.startsWith('image/');
  bool get isVideo => mimeType.startsWith('video/');
  bool get isPdf => mimeType == 'application/pdf';

  String get fileName {
    final lastSegment = storagePath.split('/').last;
    final dashIndex = lastSegment.indexOf('-');
    if (dashIndex > 0) {
      final prefix = lastSegment.substring(0, dashIndex);
      if (RegExp(r'^\d+$').hasMatch(prefix)) {
        return lastSegment.substring(dashIndex + 1);
      }
    }
    return lastSegment;
  }

  String get typeLabel {
    if (kind == 'signature') return 'Assinatura';
    if (isImage) return 'Imagem';
    if (isVideo) return 'Vídeo';
    if (isPdf) return 'PDF';
    return 'Documento';
  }

  String get sizeLabel {
    if (sizeBytes >= 1024 * 1024) {
      return '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(sizeBytes / 1024).toStringAsFixed(1)} KB';
  }
}

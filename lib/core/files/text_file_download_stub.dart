/// Fora do navegador não há download de arquivo gerado — a plataforma alvo é
/// web (ver PRODUCT.md). Mantido como no-op para o código compilar em todas.
Future<void> downloadTextFile({
  required String fileName,
  required String content,
  required String mimeType,
}) async {}

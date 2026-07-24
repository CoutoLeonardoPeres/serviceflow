import 'package:flutter/material.dart';

/// Paleta de cores do ServiceFlow.
/// Usar sempre via [Theme.of(context).colorScheme] nas telas.
/// Estas constantes são usadas apenas na construção do tema.
abstract class AppColors {
  static const Color seed = Color(0xFF6F68F8);
  static const Color surfaceBase = Color(0xFFEAEFF6);
  static const Color surfaceCanvas = Color(0xFFF1F4FA);
  static const Color surfaceRaised = Color(0xFFF4F7FC);
  static const Color surfacePressed = Color(0xFFE3E9F2);
  static const Color surfaceDeep = Color(0xFFD8E0EB);
  static const Color shadowCool = Color(0xFFB8C3D3);
  static const Color shadowDark = Color(0xFFCBD3E0);
  static const Color shadowSoft = Color(0xFFAAB7CB);
  static const Color highlight = Color(0xFFFFFFFF);
  static const Color borderSoft = Color(0xFFF8FBFF);
  static const Color electricViolet = Color(0xFF6F68F8);
  static const Color aquaPulse = Color(0xFF3BC8B4);
  static const Color ink = Color(0xFF334155);
  static const Color inkMuted = Color(0xFF6C7A90);

  // Cores semânticas usadas em chips/badges de status.
  static const Color statusDraft = Color(0xFF9E9E9E);
  static const Color statusOpen = Color(0xFF1565C0);
  static const Color statusInProgress = Color(0xFFE65100);
  static const Color statusDone = Color(0xFF2E7D32);
  static const Color statusCancelled = Color(0xFFC62828);
  static const Color statusWarning = Color(0xFFF9A825);

  // Superfície alternativa para listas zebradas.
  static const Color zebra = Color(0xFFF5F7FA);
}

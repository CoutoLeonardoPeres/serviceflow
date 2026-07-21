import 'package:flutter/material.dart';

/// Paleta de cores do ServiceFlow.
/// Usar sempre via [Theme.of(context).colorScheme] nas telas.
/// Estas constantes são usadas apenas na construção do tema.
abstract class AppColors {
  // Cor seed — gera o ColorScheme Material 3 completo.
  static const Color seed = Color(0xFF1A6FE8); // azul profissional

  // Cores semânticas usadas em chips/badges de status.
  static const Color statusDraft    = Color(0xFF9E9E9E);
  static const Color statusOpen     = Color(0xFF1565C0);
  static const Color statusInProgress = Color(0xFFE65100);
  static const Color statusDone     = Color(0xFF2E7D32);
  static const Color statusCancelled = Color(0xFFC62828);
  static const Color statusWarning  = Color(0xFFF9A825);

  // Superfície alternativa para listas zebradas.
  static const Color zebra = Color(0xFFF5F7FA);
}

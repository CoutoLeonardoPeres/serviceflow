import 'package:flutter/material.dart';

/// Paleta de cores do ServiceFlow.
/// Usar sempre via [Theme.of(context).colorScheme] nas telas.
/// Estas constantes são usadas apenas na construção do tema.
abstract class AppColors {
  static const Color background = Color(0xFFE0E5EC);
  static const Color foreground = Color(0xFF3D4852);
  static const Color muted = Color(0xFF6B7280);
  static const Color placeholder = Color(0xFFA0AEC0);
  static const Color primary = Color(0xFF6F68F8);
  static const Color primaryLight = Color(0xFF8D87FA);
  static const Color success = Color(0xFF38B2AC);
  static const Color shadowDark = Color.fromRGBO(163, 177, 198, 0.65);
  static const Color shadowLight = Color.fromRGBO(255, 255, 255, 0.55);
  static const Color shadowDarkStrong = Color.fromRGBO(163, 177, 198, 0.75);
  static const Color shadowLightStrong = Color.fromRGBO(255, 255, 255, 0.65);
  static const double radiusContainer = 32;
  static const double radiusBase = 16;
  static const double radiusInner = 12;
  static const double radiusPill = 999;
  static const Duration motion = Duration(milliseconds: 300);
  static const Curve motionCurve = Curves.easeOut;

  // Compatibility aliases used by existing screens while they migrate.
  static const Color seed = primary;
  static const Color surfaceBase = background;
  static const Color surfaceCanvas = background;
  static const Color surfaceRaised = background;
  static const Color surfacePressed = background;
  static const Color surfaceDeep = Color(0xFFD6DCE5);
  static const Color shadowCool = shadowDark;
  static const Color shadowSoft = shadowDark;
  static const Color highlight = shadowLight;
  static const Color borderSoft = Color.fromRGBO(255, 255, 255, 0.42);
  static const Color electricViolet = primary;
  static const Color aquaPulse = success;
  static const Color ink = foreground;
  static const Color inkMuted = muted;

  // Cores semânticas usadas em chips/badges de status.
  static const Color statusDraft = Color(0xFF9E9E9E);
  static const Color statusOpen = Color(0xFF1565C0);
  static const Color statusInProgress = Color(0xFFE65100);
  static const Color statusDone = Color(0xFF2E7D32);
  static const Color statusCancelled = Color(0xFFC62828);
  static const Color statusWarning = Color(0xFFF9A825);

  // Superfície alternativa para listas zebradas.
  static const Color zebra = Color(0xFFDCE2EA);
}

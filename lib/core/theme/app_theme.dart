import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'app_colors.dart';

class AppTheme {
  AppTheme._();

  // ── Tema claro ──────────────────────────────────────────────────────────────
  static ThemeData get light {
    const colorScheme = ColorScheme.light(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.success,
      onSecondary: Colors.white,
      surface: AppColors.background,
      onSurface: AppColors.foreground,
    );
    return _build(colorScheme);
  }

  // ── Tema escuro (preparado, não ativado no MVP) ──────────────────────────
  static ThemeData get dark {
    const colorScheme = ColorScheme.dark(
      primary: AppColors.primary,
      secondary: AppColors.success,
    );
    return _build(colorScheme);
  }

  static ThemeData _build(ColorScheme colorScheme) {
    final displayFont = GoogleFonts.plusJakartaSansTextTheme();
    final bodyFont = GoogleFonts.dmSansTextTheme();
    final textTheme = bodyFont.copyWith(
      displayLarge: displayFont.displayLarge!.copyWith(
        color: AppColors.ink,
        fontSize: 52,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
      displayMedium: displayFont.displayMedium!.copyWith(
        color: AppColors.ink,
        fontSize: 42,
        fontWeight: FontWeight.w800,
        letterSpacing: 0,
      ),
      headlineMedium: displayFont.headlineMedium!.copyWith(
        color: AppColors.ink,
        fontSize: 34,
        fontWeight: FontWeight.w800,
      ),
      headlineSmall: displayFont.headlineSmall!.copyWith(
        color: AppColors.ink,
        fontSize: 28,
        fontWeight: FontWeight.w800,
      ),
      titleLarge: displayFont.titleLarge!.copyWith(
        color: AppColors.ink,
        fontSize: 24,
        fontWeight: FontWeight.w700,
      ),
      titleMedium: displayFont.titleMedium!.copyWith(
        color: AppColors.ink,
        fontSize: 18,
        fontWeight: FontWeight.w700,
      ),
      bodyLarge: bodyFont.bodyLarge!.copyWith(
        color: AppColors.ink,
        fontSize: 16,
        fontWeight: FontWeight.w500,
      ),
      bodyMedium: bodyFont.bodyMedium!.copyWith(
        color: AppColors.inkMuted,
        fontSize: 14,
        fontWeight: FontWeight.w500,
      ),
      labelLarge: bodyFont.labelLarge!.copyWith(
        color: AppColors.ink,
        fontSize: 14,
        fontWeight: FontWeight.w700,
      ),
      bodySmall: bodyFont.bodySmall!.copyWith(
        color: AppColors.inkMuted,
        fontSize: 12,
        fontWeight: FontWeight.w500,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: colorScheme,
      textTheme: textTheme,
      scaffoldBackgroundColor: AppColors.surfaceBase,
      canvasColor: AppColors.surfaceBase,
      splashFactory: InkSparkle.splashFactory,
      dialogTheme: DialogThemeData(
        backgroundColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusContainer),
        ),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: AppColors.surfaceRaised,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusBase),
          side: BorderSide(
            color: AppColors.borderSoft.withValues(alpha: 0.92),
          ),
        ),
        elevation: 0,
        textStyle: textTheme.bodyMedium?.copyWith(
          color: AppColors.ink,
          fontWeight: FontWeight.w600,
        ),
      ),
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor:
              const WidgetStatePropertyAll(AppColors.surfaceRaised),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppColors.radiusBase),
              side: BorderSide(
                color: AppColors.borderSoft.withValues(alpha: 0.92),
              ),
            ),
          ),
        ),
      ),
      dropdownMenuTheme: DropdownMenuThemeData(
        textStyle: textTheme.bodyLarge,
        menuStyle: MenuStyle(
          backgroundColor:
              const WidgetStatePropertyAll(AppColors.surfaceRaised),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppColors.radiusBase),
              side: BorderSide(
                color: AppColors.borderSoft.withValues(alpha: 0.92),
              ),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: AppColors.surfacePressed,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppColors.radiusBase),
            borderSide: BorderSide(
              color: AppColors.borderSoft.withValues(alpha: 0.95),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppColors.radiusBase),
            borderSide: BorderSide(
              color: AppColors.borderSoft.withValues(alpha: 0.95),
            ),
          ),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: AppColors.ink,
        contentTextStyle: textTheme.bodyMedium?.copyWith(
          color: Colors.white,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusBase),
        ),
        behavior: SnackBarBehavior.floating,
      ),

      // ── AppBar ──
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: AppColors.ink,
          fontSize: 20,
          fontWeight: FontWeight.w800,
        ),
      ),

      // ── Cards ──
      cardTheme: CardThemeData(
        elevation: 0,
        shadowColor: AppColors.shadowCool.withValues(alpha: 0.22),
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusContainer),
          side: BorderSide(
            color: AppColors.borderSoft.withValues(alpha: 0.92),
            width: 1,
          ),
        ),
        color: AppColors.surfaceRaised,
        margin: EdgeInsets.zero,
      ),

      // ── Inputs ──
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: AppColors.surfacePressed,
        labelStyle: const TextStyle(
          color: AppColors.inkMuted,
          fontWeight: FontWeight.w600,
        ),
        hintStyle: const TextStyle(
          color: AppColors.inkMuted,
          fontWeight: FontWeight.w500,
        ),
        prefixIconColor: AppColors.inkMuted,
        suffixIconColor: AppColors.inkMuted,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusBase),
          borderSide: BorderSide(
            color: AppColors.borderSoft.withValues(alpha: 0.95),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusBase),
          borderSide: BorderSide(
            color: AppColors.borderSoft.withValues(alpha: 0.95),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusBase),
          borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: colorScheme.error),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(22),
          borderSide: BorderSide(color: colorScheme.error, width: 1.5),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
      ),

      // ── Botões ──
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          elevation: 0,
          shadowColor: colorScheme.primary.withValues(alpha: 0.34),
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.radiusBase),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      ),
      // Mesma altura do filled: sem isto os OutlinedButton caem no padrao M3
      // de 40px, e as acoes de campo (horas, material, evidencia) ficavam com
      // alvo de toque menor que as acoes que o tecnico nao deve tocar.
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(0, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.radiusBase),
          ),
          side: BorderSide(color: colorScheme.outline),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 15,
          ),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.primary,
          foregroundColor: colorScheme.onPrimary,
          elevation: 0,
          shadowColor: colorScheme.primary.withValues(alpha: 0.34),
          minimumSize: const Size(double.infinity, 48),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppColors.radiusBase),
          ),
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 15,
          ),
        ),
      ),

      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: colorScheme.primary,
          textStyle: const TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 14,
          ),
        ),
      ),

      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: colorScheme.primary,
        foregroundColor: Colors.white,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppColors.radiusBase),
        ),
      ),

      searchBarTheme: SearchBarThemeData(
        elevation: const WidgetStatePropertyAll(0),
        backgroundColor: const WidgetStatePropertyAll(AppColors.surfacePressed),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(
              color: AppColors.borderSoft.withValues(alpha: 0.95),
            ),
          ),
        ),
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 18),
        ),
      ),

      // ── Divider ──
      dividerTheme: DividerThemeData(
        color: AppColors.surfaceDeep.withValues(alpha: 0.65),
        thickness: 1,
      ),

      // ── NavigationRail (desktop) ──
      navigationRailTheme: NavigationRailThemeData(
        backgroundColor: Colors.transparent,
        selectedIconTheme: IconThemeData(color: colorScheme.primary),
        unselectedIconTheme: IconThemeData(color: colorScheme.onSurfaceVariant),
        selectedLabelTextStyle: const TextStyle(
          fontWeight: FontWeight.w800,
          color: AppColors.ink,
        ),
        unselectedLabelTextStyle: const TextStyle(
          fontWeight: FontWeight.w600,
          color: AppColors.inkMuted,
        ),
        indicatorColor: AppColors.surfacePressed,
      ),

      // ── NavigationBar (mobile) ──
      navigationBarTheme: const NavigationBarThemeData(
        backgroundColor: AppColors.surfaceRaised,
        indicatorColor: AppColors.surfacePressed,
        labelBehavior: NavigationDestinationLabelBehavior.onlyShowSelected,
      ),
    );
  }
}

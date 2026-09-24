# ServiceFlow Visual Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Transfer the `App_Cli_Manager` neumorphic design foundation to ServiceFlow while keeping the ServiceFlow blue accent and preserving all business behavior.

**Architecture:** Centralize color, typography, radius, shadow, motion, control, dialog, and responsive-shell rules under `lib/core`. Existing feature screens continue to consume `ThemeData`, `NeomorphicPanel`, `NeomorphicInset`, `AppFormSection`, and `showAppFormDialog`, so changing these shared interfaces updates most of the app without touching data or providers. Feature-specific visual migrations follow as separate plans after this foundation is stable.

**Tech Stack:** Flutter, Material 3, Riverpod, GoRouter, `google_fonts`, Flutter widget tests.

## Global Constraints

- Use `#E0E5EC` for the base background and surfaces.
- Keep the ServiceFlow primary color `#6F68F8`; do not introduce `#9C4D6D`.
- Use Plus Jakarta Sans for display text and DM Sans for body and control text.
- Use radii `32px` for large containers, `16px` for controls, and `12px` for inner wells.
- Use 300 ms `Curves.easeOut` state transitions.
- Keep all Supabase, routing, permission, plan, repository, provider, and domain behavior unchanged.
- Preserve rounded popup clipping at every layer.
- Preserve at least 44px touch targets on mobile and keyboard focus on web.
- Do not overwrite unrelated local changes in feature and test files.

---

## File Map

- Modify `pubspec.yaml`: add the font package used by the reference app.
- Modify `lib/core/theme/app_colors.dart`: become the single visual-token source.
- Modify `lib/core/theme/app_theme.dart`: apply the reference typography and global Material control styles.
- Modify `lib/core/widgets/neomorphic.dart`: implement reference-equivalent surfaces, cards, icon wells, and buttons.
- Modify `lib/core/widgets/app_form_dialog.dart`: apply the unified rounded modal shell.
- Modify `lib/core/widgets/app_form_layout.dart`: apply the unified section and responsive-grid spacing.
- Modify `lib/core/widgets/responsive_shell.dart`: apply the unified navigation container and responsive dimensions.
- Modify `lib/core/widgets/app_loading.dart`: align loading surfaces and colors with the new tokens.
- Modify `lib/core/widgets/error_view.dart`: align error and retry states with the new components.
- Create `test/theme/app_theme_test.dart`: lock colors, fonts, radii, and control sizes.
- Create `test/widgets/neomorphic_test.dart`: lock elevated, inset, hover, and semantic behavior.
- Create `test/widgets/app_form_dialog_test.dart`: lock rounded clipping and responsive dimensions.
- Create `test/widgets/responsive_shell_test.dart`: lock desktop and compact navigation behavior.
- Create `test/widgets/app_state_widgets_test.dart`: lock loading, error, empty, and retry states.

### Task 1: Lock the design-token contract

**Files:**
- Modify: `pubspec.yaml`
- Modify: `lib/core/theme/app_colors.dart`
- Create: `test/theme/app_theme_test.dart`

**Interfaces:**
- Produces: `AppColors.background`, `foreground`, `muted`, `placeholder`, `primary`, `primaryLight`, `success`, `shadowDark`, `shadowLight`, `radiusContainer`, `radiusBase`, `radiusInner`, `motion`, and `motionCurve`.
- Consumes: no new ServiceFlow interfaces.

- [ ] **Step 1: Write the failing token test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/core/theme/app_colors.dart';

void main() {
  test('design tokens match the approved ServiceFlow palette', () {
    expect(AppColors.background, const Color(0xFFE0E5EC));
    expect(AppColors.foreground, const Color(0xFF3D4852));
    expect(AppColors.muted, const Color(0xFF6B7280));
    expect(AppColors.placeholder, const Color(0xFFA0AEC0));
    expect(AppColors.primary, const Color(0xFF6F68F8));
    expect(AppColors.success, const Color(0xFF38B2AC));
    expect(AppColors.radiusContainer, 32);
    expect(AppColors.radiusBase, 16);
    expect(AppColors.radiusInner, 12);
    expect(AppColors.motion, const Duration(milliseconds: 300));
    expect(AppColors.motionCurve, Curves.easeOut);
  });
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `flutter test test/theme/app_theme_test.dart`

Expected: FAIL because the approved token names do not exist yet.

- [ ] **Step 3: Add the font dependency and exact tokens**

Add under `dependencies` in `pubspec.yaml`:

```yaml
  google_fonts: ^8.1.0
```

Replace the visual constants in `app_colors.dart` with:

```dart
abstract final class AppColors {
  static const background = Color(0xFFE0E5EC);
  static const foreground = Color(0xFF3D4852);
  static const muted = Color(0xFF6B7280);
  static const placeholder = Color(0xFFA0AEC0);
  static const primary = Color(0xFF6F68F8);
  static const primaryLight = Color(0xFF8D87FA);
  static const success = Color(0xFF38B2AC);
  static const shadowDark = Color.fromRGBO(163, 177, 198, 0.65);
  static const shadowLight = Color.fromRGBO(255, 255, 255, 0.55);
  static const shadowDarkStrong = Color.fromRGBO(163, 177, 198, 0.75);
  static const shadowLightStrong = Color.fromRGBO(255, 255, 255, 0.65);

  static const radiusContainer = 32.0;
  static const radiusBase = 16.0;
  static const radiusInner = 12.0;
  static const radiusPill = 999.0;
  static const motion = Duration(milliseconds: 300);
  static const motionCurve = Curves.easeOut;

  static const seed = primary;
  static const surfaceBase = background;
  static const surfaceCanvas = background;
  static const surfaceRaised = background;
  static const surfacePressed = background;
  static const surfaceDeep = Color(0xFFD6DCE5);
  static const shadowCool = shadowDark;
  static const shadowSoft = shadowDark;
  static const highlight = shadowLight;
  static const borderSoft = Color.fromRGBO(255, 255, 255, 0.42);
  static const electricViolet = primary;
  static const aquaPulse = success;
  static const ink = foreground;
  static const inkMuted = muted;

  static const statusDraft = Color(0xFF7B8491);
  static const statusOpen = Color(0xFF1565C0);
  static const statusInProgress = Color(0xFFE65100);
  static const statusDone = Color(0xFF2E7D32);
  static const statusCancelled = Color(0xFFC62828);
  static const statusWarning = Color(0xFFF9A825);
  static const zebra = Color(0xFFDCE2EA);
}
```

- [ ] **Step 4: Resolve packages and rerun the test**

Run: `flutter pub get && flutter test test/theme/app_theme_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add pubspec.yaml pubspec.lock lib/core/theme/app_colors.dart test/theme/app_theme_test.dart
git commit -m "feat(ui): add approved neumorphic design tokens"
```

### Task 2: Match the reference typography and Material controls

**Files:**
- Modify: `lib/core/theme/app_theme.dart`
- Modify: `test/theme/app_theme_test.dart`

**Interfaces:**
- Consumes: `AppColors` token contract from Task 1.
- Produces: `AppTheme.light` with Plus Jakarta Sans headings, DM Sans body text, 48px controls, 16px control radii, and 32px card radii.

- [ ] **Step 1: Add failing theme assertions**

Add `import 'package:serviceflow/core/theme/app_theme.dart';` with the other imports, then append:

```dart
test('light theme uses reference typography and dimensions', () {
  final theme = AppTheme.light;
  expect(theme.scaffoldBackgroundColor, AppColors.background);
  expect(theme.textTheme.headlineSmall?.fontFamily, contains('Plus Jakarta Sans'));
  expect(theme.textTheme.bodyMedium?.fontFamily, contains('DM Sans'));
  expect(
    theme.filledButtonTheme.style?.minimumSize?.resolve({}),
    const Size(48, 48),
  );
  final cardShape = theme.cardTheme.shape as RoundedRectangleBorder;
  expect(cardShape.borderRadius, BorderRadius.circular(32));
});
```

- [ ] **Step 2: Run the test to verify the current theme fails**

Run: `flutter test test/theme/app_theme_test.dart`

Expected: FAIL because the current theme uses Inter and larger control/card radii.

- [ ] **Step 3: Rebuild `AppTheme.light` around the reference theme**

Use `GoogleFonts.plusJakartaSansTextTheme()` for display and headline styles and `GoogleFonts.dmSansTextTheme()` for body, label, and control styles. Configure:

```dart
final display = GoogleFonts.plusJakartaSansTextTheme();
final body = GoogleFonts.dmSansTextTheme();
final textTheme = body.copyWith(
  displayLarge: display.displayLarge?.copyWith(
    color: AppColors.foreground,
    fontWeight: FontWeight.w800,
    letterSpacing: 0,
  ),
  headlineSmall: display.headlineSmall?.copyWith(
    color: AppColors.foreground,
    fontWeight: FontWeight.w700,
    letterSpacing: 0,
  ),
  titleLarge: display.titleLarge?.copyWith(
    color: AppColors.foreground,
    fontWeight: FontWeight.w700,
  ),
  bodyLarge: body.bodyLarge?.copyWith(
    color: AppColors.foreground,
    height: 1.45,
  ),
  bodyMedium: body.bodyMedium?.copyWith(
    color: AppColors.foreground,
    height: 1.4,
  ),
  bodySmall: body.bodySmall?.copyWith(
    color: AppColors.muted,
    height: 1.35,
  ),
);
```

Set card radius to `AppColors.radiusContainer`, field/button/menu radius to `AppColors.radiusBase`, filled and outlined button minimum size to `Size(48, 48)`, and field padding to `EdgeInsets.symmetric(horizontal: 16, vertical: 14)`. Keep error and status colors semantic.

- [ ] **Step 4: Run focused tests**

Run: `flutter test test/theme/app_theme_test.dart test/widgets/login_screen_test.dart test/widget_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/theme/app_theme.dart test/theme/app_theme_test.dart
git commit -m "feat(ui): match reference typography and controls"
```

### Task 3: Replace neumorphic primitives with reference-equivalent widgets

**Files:**
- Modify: `lib/core/widgets/neomorphic.dart`
- Create: `test/widgets/neomorphic_test.dart`

**Interfaces:**
- Consumes: `AppColors` token contract.
- Produces: existing `NeomorphicPanel`, `NeomorphicInset`, `NeomorphicBadge`, and `NeomorphicBackdrop`; new `NeomorphicCard`, `NeomorphicIconWell`, `NeomorphicButton`, and `NeomorphicButtonVariant`.

- [ ] **Step 1: Write failing component tests**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/core/theme/app_theme.dart';
import 'package:serviceflow/core/widgets/neomorphic.dart';

void main() {
  testWidgets('panel uses approved radius and paired shadows', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: const NeomorphicPanel(child: Text('Conteúdo')),
    ));
    final container = tester.widget<Container>(find.byType(Container).first);
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.borderRadius, BorderRadius.circular(32));
    expect(decoration.boxShadow, hasLength(2));
  });

  testWidgets('primary neumorphic button exposes button semantics', (tester) async {
    var pressed = false;
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: NeomorphicButton(
        label: 'Salvar',
        onPressed: () => pressed = true,
      ),
    ));
    expect(find.bySemanticsLabel('Salvar'), findsOneWidget);
    await tester.tap(find.text('Salvar'));
    expect(pressed, isTrue);
  });
}
```

- [ ] **Step 2: Run the component tests to verify they fail**

Run: `flutter test test/widgets/neomorphic_test.dart`

Expected: FAIL because the new button/card interfaces do not exist and the panel default is 24px.

- [ ] **Step 3: Implement paired shadow helpers and shared controls**

Use the following public signatures:

```dart
enum NeomorphicButtonVariant { primary, secondary }

class NeomorphicCard extends StatefulWidget {
  const NeomorphicCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
    this.onTap,
    this.borderRadius,
  });
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
}

class NeomorphicIconWell extends StatelessWidget {
  const NeomorphicIconWell({
    super.key,
    required this.icon,
    this.size = 48,
    this.iconSize = 22,
    this.color,
  });
  final IconData icon;
  final double size;
  final double iconSize;
  final Color? color;
}

class NeomorphicButton extends StatefulWidget {
  const NeomorphicButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = NeomorphicButtonVariant.primary,
    this.icon,
    this.expanded = false,
    this.loading = false,
  });
  final String label;
  final VoidCallback? onPressed;
  final NeomorphicButtonVariant variant;
  final IconData? icon;
  final bool expanded;
  final bool loading;
}
```

Set the `NeomorphicPanel` default radius to 32, `NeomorphicInset` default radius to 16, and use the exact reference offsets: elevated `Offset(9, 9)` and `Offset(-9, -9)`, small `Offset(5, 5)` and `Offset(-5, -5)`, inset `Offset(6, 6)` and `Offset(-6, -6)`. Preserve existing constructor parameters so feature screens continue compiling.

- [ ] **Step 4: Run component and affected widget tests**

Run: `flutter test test/widgets/neomorphic_test.dart test/widgets/login_screen_test.dart test/dashboard/dashboard_screen_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/widgets/neomorphic.dart test/widgets/neomorphic_test.dart
git commit -m "feat(ui): add reference neumorphic primitives"
```

### Task 4: Standardize rounded dialogs and responsive forms

**Files:**
- Modify: `lib/core/widgets/app_form_dialog.dart`
- Modify: `lib/core/widgets/app_form_layout.dart`
- Create: `test/widgets/app_form_dialog_test.dart`
- Modify: `test/widgets/app_form_grid_span_test.dart`

**Interfaces:**
- Consumes: `NeomorphicPanel`, `NeomorphicInset`, and approved radii.
- Produces: unchanged `showAppFormDialog<T>()`, `AppFormSection`, `AppFormGrid`, and `AppFormFieldSpan` APIs.

- [ ] **Step 1: Write failing dialog clipping test**

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/core/theme/app_theme.dart';
import 'package:serviceflow/core/widgets/app_form_dialog.dart';

void main() {
  testWidgets('form dialog clips every visible layer to 32px', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light,
      home: Builder(builder: (context) {
        return TextButton(
          onPressed: () => showAppFormDialog<void>(
            context: context,
            title: 'Novo cliente',
            child: const SizedBox(height: 200),
          ),
          child: const Text('Abrir'),
        );
      }),
    ));
    await tester.tap(find.text('Abrir'));
    await tester.pumpAndSettle();
    final dialog = tester.widget<Dialog>(find.byType(Dialog));
    final shape = dialog.shape as RoundedRectangleBorder;
    expect(shape.borderRadius, BorderRadius.circular(32));
    expect(dialog.clipBehavior, Clip.antiAlias);
    expect(find.byTooltip('Fechar'), findsOneWidget);
  });
}
```

- [ ] **Step 2: Run dialog and grid tests to establish the baseline**

Run: `flutter test test/widgets/app_form_dialog_test.dart test/widgets/app_form_grid_span_test.dart`

Expected: the new dialog assertion fails because the current radius is 34px.

- [ ] **Step 3: Apply the reference dialog and form dimensions**

In `showAppFormDialog`, use `BorderRadius.circular(AppColors.radiusContainer)`, preserve transparent dialog background, `Clip.antiAlias`, desktop `maxHeight: 760`, and responsive inset padding:

```dart
final compact = MediaQuery.sizeOf(context).width < 600;
final inset = compact
    ? const EdgeInsets.all(12)
    : const EdgeInsets.symmetric(horizontal: 20, vertical: 24);
```

Use a 48px `NeomorphicIconWell` for the close action. In `AppFormSection`, use 32px radius, 20px padding, 48px icon well, 16px field spacing, and keep `AppFormGrid` column-span arithmetic unchanged.

- [ ] **Step 4: Run all shared-form tests**

Run: `flutter test test/widgets/app_form_dialog_test.dart test/widgets/app_form_grid_span_test.dart test/widgets/login_screen_test.dart`

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add lib/core/widgets/app_form_dialog.dart lib/core/widgets/app_form_layout.dart test/widgets/app_form_dialog_test.dart test/widgets/app_form_grid_span_test.dart
git commit -m "feat(ui): standardize rounded forms and dialogs"
```

### Task 5: Align responsive navigation with the reference shell

**Files:**
- Modify: `lib/core/widgets/responsive_shell.dart`
- Create: `test/widgets/responsive_shell_test.dart`

**Interfaces:**
- Consumes: existing route destinations, plan feature filtering, tenant providers, auth providers, and neumorphic primitives.
- Produces: unchanged `ResponsiveShell({required Widget child})` and `Breakpoints` APIs; new pure `ShellNavigationMode shellNavigationModeForWidth(double width)` helper.

- [ ] **Step 1: Write failing responsive-mode tests**

Create `test/widgets/responsive_shell_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/core/widgets/responsive_shell.dart';

void main() {
  test('selects mobile navigation below 600px', () {
    expect(shellNavigationModeForWidth(390), ShellNavigationMode.mobile);
    expect(shellNavigationModeForWidth(599), ShellNavigationMode.mobile);
  });

  test('selects compact rail from 600px through 1023px', () {
    expect(shellNavigationModeForWidth(600), ShellNavigationMode.compactRail);
    expect(shellNavigationModeForWidth(1023), ShellNavigationMode.compactRail);
  });

  test('selects extended rail from 1024px', () {
    expect(shellNavigationModeForWidth(1024), ShellNavigationMode.extendedRail);
    expect(shellNavigationModeForWidth(1440), ShellNavigationMode.extendedRail);
  });
}
```

- [ ] **Step 2: Run the shell tests**

Run: `flutter test test/widgets/responsive_shell_test.dart`

Expected: FAIL because `ShellNavigationMode` and `shellNavigationModeForWidth` do not exist.

- [ ] **Step 3: Apply approved shell dimensions and surfaces**

Add the pure selector and use it inside `ResponsiveShell`:

```dart
enum ShellNavigationMode { mobile, compactRail, extendedRail }

ShellNavigationMode shellNavigationModeForWidth(double width) {
  if (width < Breakpoints.mobile) return ShellNavigationMode.mobile;
  if (width < Breakpoints.desktop) return ShellNavigationMode.compactRail;
  return ShellNavigationMode.extendedRail;
}
```

Keep the existing route and permission logic. Use `AppColors.background`, remove ambient decorative plates, use `AppColors.radiusContainer`, `EdgeInsets.all(24)`, compact rail width `88`, and expanded rail width from `264` through `304`. Preserve scrollable destinations and the reachable user menu. On mobile, keep the existing navigation bar and overflow behavior.

- [ ] **Step 4: Run shell, router, and dashboard tests**

Run: `flutter test test/widgets/responsive_shell_test.dart test/router/app_router_redirect_test.dart test/dashboard/dashboard_screen_test.dart`

Expected: PASS with no overflow exceptions.

- [ ] **Step 5: Commit**

```bash
git add lib/core/widgets/responsive_shell.dart test/widgets/responsive_shell_test.dart
git commit -m "feat(ui): align responsive navigation shell"
```

### Task 6: Align loading and error states, then validate the foundation

**Files:**
- Modify: `lib/core/widgets/app_loading.dart`
- Modify: `lib/core/widgets/error_view.dart`
- Create: `test/widgets/app_state_widgets_test.dart`
- Modify: `docs/CHANGELOG.md`
- Modify: `docs/PROJECT_STATE.md`

**Interfaces:**
- Consumes: `NeomorphicPanel`, `NeomorphicIconWell`, `NeomorphicButton`, and `AppColors`.
- Produces: unchanged `AppLoading`, `SplashScreen`, `ErrorView`, and `EmptyView` public APIs.

- [ ] **Step 1: Write focused state-widget tests**

Create `test/widgets/app_state_widgets_test.dart`:

```dart
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/core/theme/app_colors.dart';
import 'package:serviceflow/core/theme/app_theme.dart';
import 'package:serviceflow/core/widgets/app_loading.dart';
import 'package:serviceflow/core/widgets/error_view.dart';
import 'package:serviceflow/core/widgets/neomorphic.dart';

void main() {
  Widget wrap(Widget child) => MaterialApp(
        theme: AppTheme.light,
        home: Scaffold(body: child),
      );

  testWidgets('loading uses shared surface and primary progress color',
      (tester) async {
    await tester.pumpWidget(wrap(const AppLoading(message: 'Carregando')));
    expect(find.byType(NeomorphicPanel), findsOneWidget);
    final progress = tester.widget<CircularProgressIndicator>(
      find.byType(CircularProgressIndicator),
    );
    expect(progress.color, AppColors.primary);
    expect(find.text('Carregando'), findsOneWidget);
  });

  testWidgets('error retry uses shared button semantics', (tester) async {
    var retried = false;
    await tester.pumpWidget(wrap(ErrorView(
      message: 'Falha',
      onRetry: () => retried = true,
    )));
    expect(find.bySemanticsLabel('Tentar novamente'), findsOneWidget);
    await tester.tap(find.text('Tentar novamente'));
    expect(retried, isTrue);
  });
}
```

- [ ] **Step 2: Run the focused tests to verify current differences**

Run: `flutter test test/widgets/app_state_widgets_test.dart`

Expected: FAIL on the new loading/error appearance assertions.

- [ ] **Step 3: Migrate loading and error states to shared components**

Use `NeomorphicIconWell` for status icons, `NeomorphicButton` for retry, `AppColors.primary` for progress, `AppColors.foreground` for main text, and `AppColors.muted` for supporting text. Keep existing copy and callbacks unchanged.

- [ ] **Step 4: Format, analyze, test, and build**

Run:

```bash
dart format lib/core test/theme test/widgets
flutter analyze
flutter test
flutter build web --dart-define-from-file=dart_defines/dev.json
```

Expected: all commands exit successfully; no overflow or missing-font errors appear.

- [ ] **Step 5: Update project documentation**

Record the completed visual foundation, approved palette, font families, and remaining feature-screen migration groups in `docs/CHANGELOG.md` and `docs/PROJECT_STATE.md`.

- [ ] **Step 6: Commit**

```bash
git add lib/core/widgets/app_loading.dart lib/core/widgets/error_view.dart test/widgets/app_state_widgets_test.dart docs/CHANGELOG.md docs/PROJECT_STATE.md
git commit -m "feat(ui): complete visual foundation migration"
```

## Follow-on Plans

After this foundation passes, create and execute these independent plans in order:

1. Authentication, onboarding, plan selection, and public screens.
2. Dashboard, shell content headers, settings, and audit screens.
3. Customers, professionals, categories, and shared registration forms.
4. Service requests, agenda, quotations, and work orders.
5. Stock, purchases, suppliers, material catalog, and imports.
6. Financials, payments, fiscal, reports, promotions, campaigns, BI, and AI placeholders.
7. Visual regression screenshots, responsive review, accessibility pass, and final hard-coded-style sweep.

Each plan must preserve feature behavior, add or update widget tests, run the related test group, and finish with a complete web build.

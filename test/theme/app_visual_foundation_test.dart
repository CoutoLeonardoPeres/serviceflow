import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/core/theme/app_colors.dart';
import 'package:serviceflow/core/theme/app_theme.dart';

void main() {
  test('exposes the App Cli Manager visual tokens with ServiceFlow blue', () {
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
  });

  testWidgets('uses Plus Jakarta Sans for display and DM Sans for body',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: Column(
            children: [
              Text('Heading', key: Key('heading')),
              Text('Body', key: Key('body')),
            ],
          ),
        ),
      ),
    );

    final theme = Theme.of(tester.element(find.byKey(const Key('heading'))));
    expect(
        theme.textTheme.headlineSmall?.fontFamily, contains('PlusJakartaSans'));
    expect(theme.textTheme.bodyMedium?.fontFamily, contains('DMSans'));
  });
}

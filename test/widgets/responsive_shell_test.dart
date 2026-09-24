import 'package:flutter_test/flutter_test.dart';
import 'package:serviceflow/core/widgets/responsive_shell.dart';

void main() {
  test('maps shell widths to the shared navigation modes', () {
    expect(shellNavigationModeForWidth(480), ShellNavigationMode.mobile);
    expect(shellNavigationModeForWidth(800), ShellNavigationMode.compactRail);
    expect(shellNavigationModeForWidth(1280), ShellNavigationMode.extendedRail);
  });
}

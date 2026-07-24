// ignore_for_file: avoid_web_libraries_in_flutter, deprecated_member_use

import 'dart:html' as html;

const _storageKey = 'serviceflow_onboarding_access_override';

bool hasOnboardingAccessOverride() =>
    html.window.sessionStorage[_storageKey] == '1';

void enableOnboardingAccessOverride() {
  html.window.sessionStorage[_storageKey] = '1';
}

void clearOnboardingAccessOverride() {
  html.window.sessionStorage.remove(_storageKey);
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vantage/models/core_entry.dart';
import 'package:vantage/screens/ios_preview_screen.dart';

void main() {
  test('iOS cannot offer or download Android/desktop emulator binaries', () {
    for (final entry in coreCatalog) {
      expect(entry.supports('ios'), isFalse, reason: entry.id);
      expect(() => entry.downloadUrl(platform: 'ios', arch: 'arm64'),
          throwsUnsupportedError,
          reason: entry.id);
    }
  });

  test('existing NES download targets are preserved', () {
    final nes = coreCatalog.firstWhere((entry) => entry.id == 'fceumm');
    expect(nes.supports('android'), isTrue);
    expect(nes.supports('windows'), isTrue);
    expect(nes.downloadUrl(platform: 'android', arch: 'arm64-v8a'),
        'https://buildbot.libretro.com/nightly/android/latest/arm64-v8a/fceumm_libretro_android.so.zip');
    expect(nes.downloadUrl(platform: 'windows'),
        'https://buildbot.libretro.com/nightly/windows/x86_64/latest/fceumm_libretro.dll.zip');
  });

  testWidgets('preview explains playback availability on a small screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(const MaterialApp(home: IosPreviewScreen()));
    expect(find.text('Game playback is not available yet.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

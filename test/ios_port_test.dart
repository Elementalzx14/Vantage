import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vantage/models/core_entry.dart';
import 'package:vantage/screens/ios_preview_screen.dart';
import 'package:vantage/services/ios_controls.dart';
import 'package:vantage/widgets/ios_gamepad.dart';

void main() {
  test('iOS cannot offer or download Android/desktop emulator binaries', () {
    for (final entry in coreCatalog) {
      expect(entry.supports('ios'), iosBundledCoreIds.contains(entry.id),
          reason: entry.id);
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

  testWidgets(
      'core screen reports actual bundle availability on a small screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    const channel = MethodChannel('com.retrostream.vantage/emulator');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel, (call) async => {'fceumm': '/bundle/fceumm.framework/fceumm'});
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null));
    await tester.pumpWidget(const MaterialApp(home: IosPreviewScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Included in this app'), findsOneWidget);
    expect(find.text('Missing from this build'), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  test('Apple controller names map to libretro controls', () {
    expect(iosGamepadMap['buttonA'], 8);
    expect(iosGamepadMap['buttonB'], 0);
    expect(iosGamepadMap['dpad - yAxis+'], 4);
    expect(iosGamepadMap['dpad - yAxis-'], 5);
    expect(iosGamepadMap['buttonMenu'], 3);
  });

  testWidgets(
      'iOS pad supports simultaneous buttons and releases cancelled touches',
      (tester) async {
    final pressed = <int>{};
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: IosGamepad(
      onDown: pressed.add,
      onUp: pressed.remove,
    ))));
    final direction = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('ios-pad-6'))),
        pointer: 1);
    final action = await tester.startGesture(
        tester.getCenter(find.byKey(const ValueKey('ios-pad-8'))),
        pointer: 2);
    expect(pressed, {6, 8});
    await action.cancel();
    expect(pressed, {6});
    await direction.up();
    expect(pressed, isEmpty);
    expect(tester.takeException(), isNull);
  });
}

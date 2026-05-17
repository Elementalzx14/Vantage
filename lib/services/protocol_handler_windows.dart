import 'dart:io';
import 'package:win32_registry/win32_registry.dart';

class ProtocolHandlerWindows {
  static Future<void> register(String scheme) async {
    if (!Platform.isWindows) return;

    try {
      final String appPath = Platform.resolvedExecutable;
      
      
      final key = Registry.currentUser.createKey('Software\\Classes\\$scheme');
      
      try {
        key.createValue(RegistryValue.string('URL Protocol', ''));
        key.createValue(RegistryValue.string('', 'URL:$scheme Protocol'));

        final iconKey = key.createKey('DefaultIcon');
        try {
          iconKey.createValue(RegistryValue.string('', '$appPath,0'));
        } finally {
          iconKey.close();
        }

        final commandKey = key.createKey('shell\\open\\command');
        try {
          commandKey.createValue(RegistryValue.string('', '"$appPath" "%1"'));
        } finally {
          commandKey.close();
        }
        
        print('Windows Protocol Registered: $scheme://');
      } finally {
        key.close();
      }
    } catch (e) {
      print('Failed to register protocol: $e');
    }
  }
}

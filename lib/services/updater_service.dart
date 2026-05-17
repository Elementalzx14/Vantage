import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import '../version.dart';

class VantageUpdate {
  final String version;
  final String releaseNotes;
  final String downloadUrl;
  final String fileName;
  final int sizeBytes;

  VantageUpdate({
    required this.version,
    required this.releaseNotes,
    required this.downloadUrl,
    required this.fileName,
    required this.sizeBytes,
  });
}

class UpdaterService {
  static final UpdaterService instance = UpdaterService._();
  UpdaterService._();

  static const _channel = MethodChannel('com.retrostream.vantage/emulator');

  bool _isNewer(String latest, String current) {
    try {
      final latestParts = latest.split('+').first.split('-').first.split('.').map(int.parse).toList();
      final currentParts = current.split('+').first.split('-').first.split('.').map(int.parse).toList();
      for (int i = 0; i < latestParts.length; i++) {
        final cur = i < currentParts.length ? currentParts[i] : 0;
        if (latestParts[i] > cur) return true;
        if (latestParts[i] < cur) return false;
      }
    } catch (_) {}
    return false;
  }

  Future<VantageUpdate?> checkForUpdate() async {
    try {
      final res = await http.get(
        Uri.parse('https://api.github.com/repos/Jellyfin-PG/Vantage/releases/latest'),
        headers: {'User-Agent': 'Vantage-Client'},
      );

      if (res.statusCode != 200) return null;

      final data = jsonDecode(res.body) as Map<String, dynamic>;
      final tagName = data['tag_name'] as String;
      final cleanLatest = tagName.replaceAll(RegExp(r'^[vV]'), '');
      final cleanCurrent = appVersion.replaceAll(RegExp(r'^[vV]'), '');

      if (!_isNewer(cleanLatest, cleanCurrent)) {
        return null; // Local version is up to date or newer
      }

      final releaseNotes = data['body'] as String? ?? 'No release notes available.';
      final assets = data['assets'] as List<dynamic>;

      String? targetUrl;
      String? targetName;
      int? targetSize;

      if (Platform.isWindows) {
        for (final asset in assets) {
          final name = asset['name'] as String;
          if (name.toLowerCase().endsWith('.zip') && name.toLowerCase().contains('windows')) {
            targetUrl = asset['browser_download_url'] as String;
            targetName = name;
            targetSize = asset['size'] as int;
            break;
          }
        }
      } else if (Platform.isAndroid) {
        String abi = 'arm64-v8a'; // Default fallback
        try {
          final fetchedAbi = await _channel.invokeMethod<String>('getAbi');
          if (fetchedAbi != null && fetchedAbi.isNotEmpty) {
            abi = fetchedAbi;
          }
        } catch (e) {
          print('VANTAGE_UPDATER: Failed to query JNI ABI: $e');
        }

        print('VANTAGE_UPDATER: Local JNI CPU ABI is: $abi');

        for (final asset in assets) {
          final name = asset['name'] as String;
          if (!name.toLowerCase().endsWith('.apk')) continue;

          bool matches = false;
          if (abi.contains('arm64') && name.contains('arm64')) {
            matches = true;
          } else if (abi.contains('v7a') && name.contains('v7a')) {
            matches = true;
          } else if (abi.contains('x86_64') && name.contains('x86_64')) {
            matches = true;
          }

          if (matches) {
            targetUrl = asset['browser_download_url'] as String;
            targetName = name;
            targetSize = asset['size'] as int;
            break;
          }
        }

        if (targetUrl == null) {
          for (final asset in assets) {
            final name = asset['name'] as String;
            if (name.toLowerCase().endsWith('.apk') && name.contains('arm64')) {
              targetUrl = asset['browser_download_url'] as String;
              targetName = name;
              targetSize = asset['size'] as int;
              break;
            }
          }
        }
      }

      if (targetUrl != null && targetName != null) {
        return VantageUpdate(
          version: tagName,
          releaseNotes: releaseNotes,
          downloadUrl: targetUrl,
          fileName: targetName,
          sizeBytes: targetSize ?? 0,
        );
      }
    } catch (e) {
      print('VANTAGE_UPDATER: Error during update check: $e');
    }
    return null;
  }

  Future<String?> downloadUpdate(VantageUpdate update, Function(double progress) onProgress) async {
    try {
      final client = http.Client();
      final req = http.Request('GET', Uri.parse(update.downloadUrl));
      final res = await client.send(req);

      if (res.statusCode != 200) {
        return null;
      }

      final contentLength = res.contentLength ?? update.sizeBytes;
      final tempDir = await getTemporaryDirectory();
      final saveFile = File(p.join(tempDir.path, update.fileName));
      final sink = saveFile.openWrite();

      int downloaded = 0;
      await for (final chunk in res.stream) {
        sink.add(chunk);
        downloaded += chunk.length;
        if (contentLength > 0) {
          onProgress(downloaded / contentLength);
        }
      }
      await sink.close();
      client.close();
      return saveFile.path;
    } catch (e) {
      print('VANTAGE_UPDATER: Error downloading update file: $e');
    }
    return null;
  }

  Future<String?> executeUpdate(String filePath) async {
    if (Platform.isWindows) {
      try {
        final executableDir = Directory(Platform.resolvedExecutable).parent.path;
        final tempDir = await getTemporaryDirectory();
        final scriptFile = File(p.join(tempDir.path, 'update.ps1'));

        final scriptContent = '''
Start-Sleep -Seconds 2
Expand-Archive -Path "$filePath" -DestinationPath "$executableDir" -Force
Start-Process -FilePath "${Platform.resolvedExecutable}"
''';
        await scriptFile.writeAsString(scriptContent);

        print('VANTAGE_UPDATER: Launching background self-update pipeline: ${scriptFile.path}');
        await Process.start(
          'powershell.exe',
          ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', scriptFile.path],
          runInShell: true,
        );
        exit(0);
      } catch (e) {
        print('VANTAGE_UPDATER: Failed to execute Windows self-update: $e');
      }
      return null;
    } else if (Platform.isAndroid) {
      try {
        final dirs = await getExternalStorageDirectories(type: StorageDirectory.downloads);
        if (dirs != null && dirs.isNotEmpty) {
          final destDir = dirs.first;
          final filename = p.basename(filePath);
          final destFile = File(p.join(destDir.path, filename));
          
          if (await destFile.exists()) {
            await destFile.delete();
          }
          
          await File(filePath).copy(destFile.path);
          print('VANTAGE_UPDATER: Copied APK to external downloads: ${destFile.path}');
          return destFile.path;
        }
      } catch (e) {
        print('VANTAGE_UPDATER: Failed to copy Android APK: $e');
      }
    }
    return null;
  }
}

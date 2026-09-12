import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:go_router/go_router.dart';
import '../main.dart';
import '../models/jellyfin_models.dart';
import 'jellyfin_api.dart';
import 'prefs.dart';
import 'core_manager.dart';
import 'path_service.dart';
import 'log_service.dart';

class LaunchService {
  static final instance = LaunchService._();
  LaunchService._();

  final _api = JellyfinApi();
  final _prefs = Prefs();
  
  final ValueNotifier<int?> downloadProgress = ValueNotifier(null);
  final ValueNotifier<String?> statusMessage = ValueNotifier(null);

  Future<void> launchItem(String itemId) async {
    try {
      statusMessage.value = 'FETCHING METADATA...';
      
      final serverUrl = await _prefs.serverUrl;
      final token = await _prefs.token;
      final userId = await _prefs.userId;

      if (serverUrl.isEmpty || token.isEmpty) {
        statusMessage.value = 'ERROR: NOT LOGGED IN';
        Future.delayed(const Duration(seconds: 3), () {
          statusMessage.value = null;
        });
        return;
      }

      final item = await _api.getItem(serverUrl, token, userId, itemId);
      await launchGame(item);
    } catch (e) {
      statusMessage.value = 'ERROR: $e';
      Future.delayed(const Duration(seconds: 3), () {
        statusMessage.value = null;
        downloadProgress.value = null;
      });
    }
  }

  Future<void> launchGame(JfItem item) async {
    final serverUrl = await _prefs.serverUrl;
    final token = await _prefs.token;
    final userId = await _prefs.userId;

    final localFile = await getLocalRomFile(item);
    if (Platform.isIOS) {
      final ext = localFile.path.split('.').last.toLowerCase();
      final core = (item.platformTag == null ? null :
          CoreManager.instance.corePathForPlatformTag(item.platformTag!)) ??
          CoreManager.instance.corePathForExtension(ext);
      // Do not download games for consoles that are not in this build yet.
      if (core == null) {
        downloadProgress.value = null;
        statusMessage.value = null;
        router.push('/ios-preview');
        return;
      }
    }
    vLog('CHECKING LOCAL ROM: ${localFile.path}');
    if (await localFile.exists()) {
      final len = await localFile.length();
      vLog('LOCAL ROM FOUND | SIZE: $len bytes');
      if (len > 1024) {
        _startEmulator(localFile.path, item, serverUrl, token, userId);
        statusMessage.value = null;
        downloadProgress.value = null;
        return;
      }
      vLog('LOCAL ROM TOO SMALL OR CORRUPT | DELETING...');
      await localFile.delete();
    }

    final downloadUrl = item.downloadUrl(serverUrl);
    vLog('STARTING ROM DOWNLOAD: $downloadUrl');
    downloadProgress.value = -1;
    statusMessage.value = 'DOWNLOADING ROM...';

    try {
      await _downloadRom(downloadUrl, localFile, (pct) {
        downloadProgress.value = pct;
      }, token: Platform.isIOS ? token : null);
      vLog('ROM DOWNLOAD SUCCESSFUL');
      _startEmulator(localFile.path, item, serverUrl, token, userId);
      downloadProgress.value = null;
      statusMessage.value = null;
    } catch (e, stack) {
      vError('ROM DOWNLOAD FAILED', e, stack);
      statusMessage.value = 'ERROR: DOWNLOAD FAILED';
      Future.delayed(const Duration(seconds: 3), () {
        downloadProgress.value = null;
        statusMessage.value = null;
      });
      rethrow;
    }
  }

  void _startEmulator(String romPath, JfItem item, String serverUrl, String token, String userId) {
    vLog('STARTING EMULATOR FLOW FOR: ${item.name} | ID: ${item.id}');
    
    // Standardize paths for Windows to avoid mix of / and \
    String finalRomPath = romPath;
    if (Platform.isWindows) {
      finalRomPath = romPath.replaceAll('/', '\\');
    }
    vLog('ROM PATH: $finalRomPath');
    
    final ext = finalRomPath.split('.').last;
    vLog('FILE EXTENSION: $ext | PLATFORM TAG: ${item.platformTag}');

    String? corePath = (item.platformTag != null
        ? CoreManager.instance.corePathForPlatformTag(item.platformTag!)
        : null) ?? CoreManager.instance.corePathForExtension(ext);
    
    if (corePath != null && Platform.isWindows) {
      corePath = corePath.replaceAll('/', '\\');
    }
    
    vLog('RESOLVED CORE PATH: $corePath');

    if (corePath == null) {
      vError('CORE RESOLUTION FAILED FOR ${item.name} (${item.platformTag} / $ext)');
      statusMessage.value = 'ERROR: NO CORE FOUND';
      Future.delayed(const Duration(seconds: 3), () {
        statusMessage.value = null;
        downloadProgress.value = null;
      });
      return;
    }

    // Verify files exist right before push
    if (!File(finalRomPath).existsSync()) {
      vError('ROM FILE MISSING AT LAUNCH TIME: $finalRomPath');
      statusMessage.value = 'ERROR: ROM FILE MISSING';
      Future.delayed(const Duration(seconds: 3), () {
        statusMessage.value = null;
        downloadProgress.value = null;
      });
      return;
    }
    if (!File(corePath).existsSync()) {
      vError('CORE FILE MISSING AT LAUNCH TIME: $corePath');
      statusMessage.value = 'ERROR: CORE FILE MISSING';
      Future.delayed(const Duration(seconds: 3), () {
        statusMessage.value = null;
        downloadProgress.value = null;
      });
      return;
    }

    vLog('PUSHING TO EMULATOR SCREEN...');
    
    router.push('/emulator', extra: {
      'romPath': finalRomPath,
      'corePath': corePath!,
      'title': item.name,
      'itemId': item.id,
      'serverUrl': serverUrl,
      'token': token,
      'userId': userId,
    });
  }

  Future<File> getLocalRomFile(JfItem item) async {
    final romsDir = await PathService.instance.romsDir;
    final platform = item.platformTag?.replaceAll(' ', '_') ?? 'unknown';
    
    String filename;
    if (item.path != null && item.path!.isNotEmpty) {
      filename = item.path!.replaceAll('\\', '/').split('/').last;
    } else {
      final safeName = item.name.replaceAll(RegExp(r'[^a-zA-Z0-9._\- ]'), '_');
      filename = '$safeName.rom';
    }
    
    return File('$romsDir/$platform/$filename');
  }

  Future<void> _downloadRom(String url, File dest, void Function(int) onProgress, {String? token}) async {
    await dest.parent.create(recursive: true);
    final request = http.Request('GET', Uri.parse(url));
    if (token != null) request.headers['Authorization'] = 'MediaBrowser Token="$token"';
    final streamed = await request.send();
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) throw Exception('HTTP ${streamed.statusCode}');
    final total = streamed.contentLength ?? 0;
    var done = 0;
    final target = Platform.isIOS ? File('${dest.path}.part') : dest;
    final sink = target.openWrite();
    onProgress(-1);
    try {
      await for (final chunk in streamed.stream) {
        sink.add(chunk);
        done += chunk.length;
        if (total > 0) onProgress((done * 100 ~/ total));
      }
      await sink.flush();
    } finally {
      await sink.close();
    }
    if (Platform.isIOS) {
      if (done == 0 || (total > 0 && done != total)) {
        throw Exception('Incomplete ROM download');
      }
      await target.rename(dest.path);
    }
  }
}

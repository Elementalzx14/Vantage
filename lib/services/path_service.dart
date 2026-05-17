import 'dart:io';
import 'package:path_provider/path_provider.dart';

class PathService {
  PathService._();
  static final instance = PathService._();

  Directory? _baseDir;

  Future<void> init() async {
    if (_baseDir != null) return;

    if (Platform.isWindows) {
      
      final exePath = Platform.resolvedExecutable;
      final exeDir = Directory(exePath).parent;

      
      final portableMarker = File('${exeDir.path}/.portable');
      if (portableMarker.existsSync()) {
        _baseDir = exeDir;
      } else {
        
        final testFile = File('${exeDir.path}/.vantage_write_test');
        try {
          testFile.writeAsStringSync('test');
          testFile.deleteSync();
          _baseDir = exeDir;
        } catch (_) {
          
        }
      }
    }

    _baseDir ??= await getApplicationSupportDirectory();
  }

  Future<Directory> get baseDir async {
    await init();
    return _baseDir!;
  }

  Future<String> get coresDir async {
    final base = await baseDir;
    return '${base.path}/vantage/cores';
  }

  Future<String> get romsDir async {
    final base = await baseDir;
    return '${base.path}/vantage/roms';
  }

  Future<String> get systemDir async {
    final base = await baseDir;
    return '${base.path}/vantage/system';
  }

  Future<String> get logsDir async {
    final base = await baseDir;
    return '${base.path}/vantage/logs';
  }

  Future<File> get logFile async {
    final dir = await logsDir;
    await Directory(dir).create(recursive: true);
    return File('$dir/vantage.log');
  }
}

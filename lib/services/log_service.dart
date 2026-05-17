import 'dart:io';
import 'path_service.dart';

class LogService {
  LogService._();
  static final instance = LogService._();

  File? _logFile;

  Future<void> init() async {
    if (_logFile != null) return;
    _logFile = await PathService.instance.logFile;
    
    
    if (await _logFile!.exists() && await _logFile!.length() > 5 * 1024 * 1024) {
      await _logFile!.writeAsString('--- LOG ROTATED ---\n');
    }

    log('--- VANTAGE STARTUP ---');
  }

  void log(String message) {
    final timestamp = DateTime.now().toIso8601String();
    final line = '[$timestamp] $message\n';
    
    
    print(line.trim());

    
    if (_logFile != null) {
      _logFile!.writeAsStringSync(line, mode: FileMode.append);
    }
  }

  void error(String message, [dynamic e, StackTrace? stack]) {
    var fullMsg = 'ERROR: $message';
    if (e != null) fullMsg += ' | Exception: $e';
    log(fullMsg);
    if (stack != null) {
      log('STACKTRACE:\n$stack');
    }
  }
}

void vLog(String msg) => LogService.instance.log(msg);
void vError(String msg, [dynamic e, StackTrace? stack]) => LogService.instance.error(msg, e, stack);

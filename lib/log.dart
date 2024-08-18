import 'package:logging/logging.dart';

class Log {
  final Logger log;

  static const _levels = {
    'shout': Level.SHOUT,
    'severe': Level.SEVERE,
    'warning': Level.WARNING,
    'info': Level.INFO,
    'config': Level.CONFIG,
    'fine': Level.FINE,
    'finer': Level.FINER,
    'finest': Level.FINEST,
    'all': Level.ALL
    };


  Log({String logname = 'log'}) : log = Logger(logname) {
    log.onRecord.listen((record) {
      // TODO: Update this to log somewhere useful or switch to Flutter debugprint
      print('"${DateTime.now()}", "${record.level}", "${(record.object as Map)['library']}", "${(record.object as Map)['message']}"');});
  }

  void logMessage(String message, String library, {String level='info'}) {
    if (_levels.containsKey(level)) {
      log.log(_levels[level]!, {'library': _sanitizeString(library), 'message': _sanitizeString(message)});
    } else {
      log.log(Level.SEVERE, {'library': _sanitizeString(library), 'message': 'Invalid level ($level) submitted! Original message:  ${_sanitizeString(message)}'});
    }
  }

  String _sanitizeString(String str, {int maxLogLength = 150}) {
    final sanitizedString = str.replaceAll('"', '`');
    final strLength = sanitizedString.length;
    if (strLength > maxLogLength) {
      return sanitizedString.substring(0, maxLogLength);
    }
    return sanitizedString;
  }
}
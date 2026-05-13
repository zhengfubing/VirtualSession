import 'dart:collection';
import 'package:flutter/foundation.dart';

class LogEntry {
  final DateTime time;
  final String level;
  final String message;

  LogEntry({required this.time, required this.level, required this.message});
}

class LogService {
  static final LogService instance = LogService._internal();
  LogService._internal();

  final _logs = Queue<LogEntry>();
  static const _maxLogs = 500;

  void info(String message) => _add('INFO', message);
  void warn(String message) => _add('WARN', message);
  void error(String message) => _add('ERROR', message);

  void _add(String level, String message) {
    final entry = LogEntry(time: DateTime.now(), level: level, message: message);
    _logs.add(entry);
    if (_logs.length > _maxLogs) _logs.removeFirst();
    debugPrint('[${level}] $message');
  }

  List<LogEntry> get logs => _logs.toList();
  void clear() => _logs.clear();
}

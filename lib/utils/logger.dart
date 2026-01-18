import 'dart:developer' as developer;
import 'package:flutter/foundation.dart';

/// Log levels for filtering and categorizing log messages
enum LogLevel {
  verbose(0, 'V'),
  debug(1, 'D'),
  info(2, 'I'),
  warning(3, 'W'),
  error(4, 'E'),
  fatal(5, 'F');

  const LogLevel(this.priority, this.prefix);
  final int priority;
  final String prefix;
}

/// Configuration for the logger
class LoggerConfig {
  const LoggerConfig({
    this.minLevel = LogLevel.verbose,
    this.enableColors = true,
    this.showTimestamp = true,
    this.showCaller = true,
  });

  final LogLevel minLevel;
  final bool enableColors;
  final bool showTimestamp;
  final bool showCaller;

  static const LoggerConfig production = LoggerConfig(
    minLevel: LogLevel.warning,
    enableColors: false,
    showTimestamp: true,
    showCaller: false,
  );

  static const LoggerConfig development = LoggerConfig(
    minLevel: LogLevel.verbose,
    enableColors: true,
    showTimestamp: true,
    showCaller: true,
  );
}

/// A production-grade logging system for Flutter applications
class Logger {
  Logger._();

  static final Logger _instance = Logger._();
  static Logger get instance => _instance;

  LoggerConfig _config = kDebugMode 
      ? LoggerConfig.development 
      : LoggerConfig.production;

  /// Configure the logger
  static void configure(LoggerConfig config) {
    _instance._config = config;
  }

  /// Get a named logger for a specific component
  static NamedLogger getLogger(String name) => NamedLogger(name);

  // ANSI color codes for terminal output
  static const String _reset = '\x1B[0m';
  static const String _red = '\x1B[31m';
  static const String _green = '\x1B[32m';
  static const String _yellow = '\x1B[33m';
  static const String _magenta = '\x1B[35m';
  static const String _cyan = '\x1B[36m';
  static const String _white = '\x1B[37m';

  String _getColorForLevel(LogLevel level) {
    if (!_config.enableColors) return '';
    return switch (level) {
      LogLevel.verbose => _white,
      LogLevel.debug => _cyan,
      LogLevel.info => _green,
      LogLevel.warning => _yellow,
      LogLevel.error => _red,
      LogLevel.fatal => _magenta,
    };
  }

  String _formatTimestamp() {
    if (!_config.showTimestamp) return '';
    final now = DateTime.now();
    return '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}.'
        '${now.millisecond.toString().padLeft(3, '0')}';
  }

  String _getCaller() {
    if (!_config.showCaller) return '';
    try {
      final trace = StackTrace.current.toString().split('\n');
      // Find the first frame outside of logger.dart
      for (final frame in trace) {
        if (!frame.contains('logger.dart') && 
            !frame.contains('<asynchronous suspension>') &&
            frame.trim().isNotEmpty) {
          final match = RegExp(r'\((.+?):(\d+):\d+\)').firstMatch(frame);
          if (match != null) {
            final file = match.group(1)?.split('/').last ?? 'unknown';
            final line = match.group(2) ?? '?';
            return '$file:$line';
          }
        }
      }
    } catch (_) {
      // Ignore stack trace parsing errors
    }
    return '';
  }

  void _log(
    LogLevel level,
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    if (level.priority < _config.minLevel.priority) return;

    final buffer = StringBuffer();
    final color = _getColorForLevel(level);
    final resetColor = _config.enableColors ? _reset : '';

    // Build log message
    buffer.write('$color[${level.prefix}]$resetColor ');
    
    if (_config.showTimestamp) {
      buffer.write('${_formatTimestamp()} ');
    }
    
    if (tag != null) {
      buffer.write('[$tag] ');
    }
    
    if (_config.showCaller) {
      final caller = _getCaller();
      if (caller.isNotEmpty) {
        buffer.write('($caller) ');
      }
    }
    
    buffer.write(message);

    final logMessage = buffer.toString();

    // Use developer.log for debug builds (appears in DevTools)
    // Use print for release (can be captured by crash reporting)
    if (kDebugMode) {
      developer.log(
        logMessage,
        name: tag ?? 'App',
        level: level.priority * 200,
        error: error,
        stackTrace: stackTrace,
      );
    } else if (level.priority >= _config.minLevel.priority) {
      // In production, only log warnings and above
      // ignore: avoid_print
      print(logMessage);
      if (error != null) {
        // ignore: avoid_print
        print('Error: $error');
      }
      if (stackTrace != null) {
        // ignore: avoid_print
        print('StackTrace: $stackTrace');
      }
    }
  }

  // Static convenience methods
  static void v(String message, {String? tag}) {
    _instance._log(LogLevel.verbose, message, tag: tag);
  }

  static void d(String message, {String? tag}) {
    _instance._log(LogLevel.debug, message, tag: tag);
  }

  static void i(String message, {String? tag}) {
    _instance._log(LogLevel.info, message, tag: tag);
  }

  static void w(String message, {String? tag, Object? error}) {
    _instance._log(LogLevel.warning, message, tag: tag, error: error);
  }

  static void e(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _instance._log(
      LogLevel.error,
      message,
      tag: tag,
      error: error,
      stackTrace: stackTrace,
    );
  }

  static void f(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
  }) {
    _instance._log(
      LogLevel.fatal,
      message,
      tag: tag,
      error: error,
      stackTrace: stackTrace,
    );
  }
}

/// A named logger for component-specific logging
class NamedLogger {
  NamedLogger(this.name);

  final String name;

  void v(String message) => Logger.v(message, tag: name);
  void d(String message) => Logger.d(message, tag: name);
  void i(String message) => Logger.i(message, tag: name);
  void w(String message, {Object? error}) => 
      Logger.w(message, tag: name, error: error);
  void e(String message, {Object? error, StackTrace? stackTrace}) =>
      Logger.e(message, tag: name, error: error, stackTrace: stackTrace);
  void f(String message, {Object? error, StackTrace? stackTrace}) =>
      Logger.f(message, tag: name, error: error, stackTrace: stackTrace);
}

/// Mixin for classes that need logging capability
mixin Loggable {
  late final NamedLogger _logger = Logger.getLogger(runtimeType.toString());
  
  @protected
  NamedLogger get logger => _logger;
}
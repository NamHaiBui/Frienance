import 'dart:collection';
import 'dart:developer' as developer;
import 'dart:io';

import 'package:flutter/foundation.dart';

/// Environment variable name to check for development mode.
/// Set `FRIENANCE_ENV=development` to enable direct console logging.
const String _envVariableName = 'FRIENANCE_ENV';
const String _developmentValue = 'development';

/// Check if we're in development environment via env variable.
bool get isDevelopmentEnvironment {
  final envValue = Platform.environment[_envVariableName];
  return envValue?.toLowerCase() == _developmentValue || kDebugMode;
}

/// Unified log levels for filtering and categorizing log messages.
/// Merges LogLevel and LogLevel into a single enum.
enum LogLevel {
  verbose(0, 'V'),
  debug(1, 'D'),
  info(2, 'I'),
  warning(3, 'W'),
  error(4, 'E'),
  fatal(5, 'F'),
  none(6, 'N');

  const LogLevel(this.priority, this.prefix);
  final int priority;
  final String prefix;

  /// Check if this level should log given a minimum level.
  bool shouldLog(LogLevel minLevel) => priority >= minLevel.priority;
}

/// Configuration for the unified logger.
class LoggerConfig {
  const LoggerConfig({
    this.minLevel = LogLevel.verbose,
    this.enableColors = true,
    this.showTimestamp = true,
    this.showCaller = true,
    this.logDirectory,
    this.maxBufferEntries = 500,
    this.maxBufferSizeBytes = 1024 * 1024, // 1MB
    this.autoFlushOnError = true,
  });

  final LogLevel minLevel;
  final bool enableColors;
  final bool showTimestamp;
  final bool showCaller;
  
  /// Directory for log file output (production mode).
  final String? logDirectory;
  
  /// Maximum entries in the log buffer.
  final int maxBufferEntries;
  
  /// Maximum buffer size in bytes.
  final int maxBufferSizeBytes;
  
  /// Automatically flush buffer to file on error/fatal logs.
  final bool autoFlushOnError;

  static const LoggerConfig production = LoggerConfig(
    minLevel: LogLevel.warning,
    enableColors: false,
    showTimestamp: true,
    showCaller: false,
    autoFlushOnError: true,
  );

  static const LoggerConfig development = LoggerConfig(
    minLevel: LogLevel.verbose,
    enableColors: true,
    showTimestamp: true,
    showCaller: true,
    autoFlushOnError: false,
  );

  LoggerConfig copyWith({
    LogLevel? minLevel,
    bool? enableColors,
    bool? showTimestamp,
    bool? showCaller,
    String? logDirectory,
    int? maxBufferEntries,
    int? maxBufferSizeBytes,
    bool? autoFlushOnError,
  }) {
    return LoggerConfig(
      minLevel: minLevel ?? this.minLevel,
      enableColors: enableColors ?? this.enableColors,
      showTimestamp: showTimestamp ?? this.showTimestamp,
      showCaller: showCaller ?? this.showCaller,
      logDirectory: logDirectory ?? this.logDirectory,
      maxBufferEntries: maxBufferEntries ?? this.maxBufferEntries,
      maxBufferSizeBytes: maxBufferSizeBytes ?? this.maxBufferSizeBytes,
      autoFlushOnError: autoFlushOnError ?? this.autoFlushOnError,
    );
  }
}

/// A single log entry for buffering.
class LogEntry {
  const LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.tag,
    this.error,
    this.stackTrace,
    this.context = const {},
  });

  final DateTime timestamp;
  final LogLevel level;
  final String message;
  final String? tag;
  final Object? error;
  final StackTrace? stackTrace;
  final Map<String, dynamic> context;

  /// Estimated size in bytes for buffer management.
  int get estimatedSize {
    var size = message.length + 50; // Base overhead
    if (tag != null) size += tag!.length;
    if (error != null) size += error.toString().length;
    if (stackTrace != null) size += 500; // Rough estimate
    return size;
  }

  /// Format the entry for display/file output.
  String format({bool includeColor = false, String color = '', String reset = ''}) {
    final buffer = StringBuffer();
    
    if (includeColor) buffer.write(color);
    buffer.write('[${level.prefix}]');
    if (includeColor) buffer.write(reset);
    buffer.write(' ');
    
    buffer.write('[${timestamp.toIso8601String()}]');
    if (tag != null) buffer.write(' [$tag]');
    buffer.write(' $message');
    if (error != null) buffer.write('\n  Error: $error');
    if (stackTrace != null) buffer.write('\n  StackTrace:\n$stackTrace');
    if (context.isNotEmpty) buffer.write('\n  Context: $context');
    
    return buffer.toString();
  }
}

/// Log buffer for production diagnostic log dumping.
class LogBuffer {
  LogBuffer({
    this.maxEntries = 500,
    this.maxSizeBytes = 1024 * 1024, // 1MB
  });

  final int maxEntries;
  final int maxSizeBytes;

  final Queue<LogEntry> _entries = Queue<LogEntry>();
  int _currentSizeBytes = 0;

  /// Add a log entry to the buffer.
  void add(LogEntry entry) {
    final entrySize = entry.estimatedSize;
    
    // Remove old entries if we'd exceed limits
    while (_entries.isNotEmpty && 
           (_entries.length >= maxEntries || 
            _currentSizeBytes + entrySize > maxSizeBytes)) {
      final removed = _entries.removeFirst();
      _currentSizeBytes -= removed.estimatedSize;
    }
    
    _entries.add(entry);
    _currentSizeBytes += entrySize;
  }

  /// Get all log entries.
  List<LogEntry> getEntries() => _entries.toList();

  /// Get entries since a specific time.
  List<LogEntry> getEntriesSince(DateTime since) {
    return _entries.where((e) => e.timestamp.isAfter(since)).toList();
  }

  /// Get entries of a specific level or higher.
  List<LogEntry> getEntriesOfLevel(LogLevel minLevel) {
    return _entries.where((e) => e.level.shouldLog(minLevel)).toList();
  }

  /// Dump logs to a file.
  Future<File> dumpToFile(String directory) async {
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final file = File('$directory/log_dump_$timestamp.txt');
    
    final buffer = StringBuffer();
    buffer.writeln('=== Log Dump: $timestamp ===');
    buffer.writeln('Total entries: ${_entries.length}');
    buffer.writeln('');
    
    for (final entry in _entries) {
      buffer.writeln(entry.format());
    }
    
    await file.create(recursive: true);
    await file.writeAsString(buffer.toString());
    
    return file;
  }

  /// Format logs as a string for display.
  String formatAll() {
    return _entries.map((e) => e.format()).join('\n');
  }

  /// Clear all entries.
  void clear() {
    _entries.clear();
    _currentSizeBytes = 0;
  }

  /// Number of entries in the buffer.
  int get length => _entries.length;

  /// Whether the buffer is empty.
  bool get isEmpty => _entries.isEmpty;
}

/// Unified production-grade logging system for Flutter applications.
/// 
/// In development environment (FRIENANCE_ENV=development or kDebugMode):
/// - Logs directly to console with colors and caller info.
/// 
/// In production environment:
/// - Buffers logs in memory.
/// - Writes to log file on demand or automatically on error.
class Logger {
  Logger._() {
    _buffer = LogBuffer(
      maxEntries: _config.maxBufferEntries,
      maxSizeBytes: _config.maxBufferSizeBytes,
    );
  }

  static final Logger _instance = Logger._();
  static Logger get instance => _instance;

  LoggerConfig _config = isDevelopmentEnvironment 
      ? LoggerConfig.development 
      : LoggerConfig.production;

  late LogBuffer _buffer;

  /// Configure the logger.
  static void configure(LoggerConfig config) {
    _instance._config = config;
    _instance._buffer = LogBuffer(
      maxEntries: config.maxBufferEntries,
      maxSizeBytes: config.maxBufferSizeBytes,
    );
  }

  /// Get current configuration.
  static LoggerConfig get config => _instance._config;

  /// Get the log buffer (for manual inspection/dumping).
  static LogBuffer get buffer => _instance._buffer;

  /// Get a named logger for a specific component.
  static NamedLogger getLogger(String name) => NamedLogger(name);

  /// Set the log directory for file output.
  static void setLogDirectory(String directory) {
    _instance._config = _instance._config.copyWith(logDirectory: directory);
  }

  /// Manually flush the buffer to a log file.
  static Future<File?> flushToFile([String? directory]) async {
    final dir = directory ?? _instance._config.logDirectory;
    if (dir == null) {
      if (isDevelopmentEnvironment) {
        // ignore: avoid_print
        print('[Logger] No log directory configured, cannot flush to file');
      }
      return null;
    }
    return _instance._buffer.dumpToFile(dir);
  }

  /// Clear the log buffer.
  static void clearBuffer() => _instance._buffer.clear();

  // ANSI color codes for terminal output
  static const String _reset = '\x1B[0m';
  static const String _red = '\x1B[31m';
  static const String _green = '\x1B[32m';
  static const String _yellow = '\x1B[33m';
  static const String _magenta = '\x1B[35m';
  static const String _cyan = '\x1B[36m';
  static const String _white = '\x1B[37m';
  static const String _gray = '\x1B[90m';

  String _getColorForLevel(LogLevel level) {
    if (!_config.enableColors) return '';
    return switch (level) {
      LogLevel.verbose => _gray,
      LogLevel.debug => _cyan,
      LogLevel.info => _green,
      LogLevel.warning => _yellow,
      LogLevel.error => _red,
      LogLevel.fatal => _magenta,
      LogLevel.none => _white,
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
      // Find the first frame outside of unified_logger.dart
      for (final frame in trace) {
        if (!frame.contains('unified_logger.dart') && 
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
    Map<String, dynamic> context = const {},
  }) {
    if (level.priority < _config.minLevel.priority) return;

    final timestamp = DateTime.now();
    final entry = LogEntry(
      timestamp: timestamp,
      level: level,
      message: message,
      tag: tag,
      error: error,
      stackTrace: stackTrace,
      context: context,
    );

    if (isDevelopmentEnvironment) {
      // Development: Log directly to console
      _logToConsole(entry);
    } else {
      // Production: Buffer the log
      _buffer.add(entry);
      
      // Auto-flush on error/fatal if configured
      if (_config.autoFlushOnError && 
          (level == LogLevel.error || level == LogLevel.fatal)) {
        flushToFile();
      }
    }
  }

  void _logToConsole(LogEntry entry) {
    final buffer = StringBuffer();
    final color = _getColorForLevel(entry.level);
    final resetColor = _config.enableColors ? _reset : '';

    // Build log message
    buffer.write('$color[${entry.level.prefix}]$resetColor ');
    
    if (_config.showTimestamp) {
      buffer.write('${_formatTimestamp()} ');
    }
    
    if (entry.tag != null) {
      buffer.write('[${entry.tag}] ');
    }
    
    if (_config.showCaller) {
      final caller = _getCaller();
      if (caller.isNotEmpty) {
        buffer.write('($caller) ');
      }
    }
    
    buffer.write(entry.message);

    final logMessage = buffer.toString();

    // Use developer.log for debug builds (appears in DevTools)
    if (kDebugMode) {
      developer.log(
        logMessage,
        name: entry.tag ?? 'App',
        level: entry.level.priority * 200,
        error: entry.error,
        stackTrace: entry.stackTrace,
      );
    } else {
      // Fallback to print
      // ignore: avoid_print
      print(logMessage);
      if (entry.error != null) {
        // ignore: avoid_print
        print('Error: ${entry.error}');
      }
      if (entry.stackTrace != null) {
        // ignore: avoid_print
        print('StackTrace: ${entry.stackTrace}');
      }
    }

    if (entry.context.isNotEmpty && kDebugMode) {
      developer.log('  Context: ${entry.context}', name: entry.tag ?? 'App');
    }
  }

  // Static convenience methods
  static void v(String message, {String? tag, Map<String, dynamic>? context}) {
    _instance._log(LogLevel.verbose, message, tag: tag, context: context ?? {});
  }

  static void d(String message, {String? tag, Map<String, dynamic>? context}) {
    _instance._log(LogLevel.debug, message, tag: tag, context: context ?? {});
  }

  static void i(String message, {String? tag, Map<String, dynamic>? context}) {
    _instance._log(LogLevel.info, message, tag: tag, context: context ?? {});
  }

  static void w(String message, {String? tag, Object? error, Map<String, dynamic>? context}) {
    _instance._log(LogLevel.warning, message, tag: tag, error: error, context: context ?? {});
  }

  static void e(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) {
    _instance._log(
      LogLevel.error,
      message,
      tag: tag,
      error: error,
      stackTrace: stackTrace,
      context: context ?? {},
    );
  }

  static void f(
    String message, {
    String? tag,
    Object? error,
    StackTrace? stackTrace,
    Map<String, dynamic>? context,
  }) {
    _instance._log(
      LogLevel.fatal,
      message,
      tag: tag,
      error: error,
      stackTrace: stackTrace,
      context: context ?? {},
    );
  }
}

/// A named logger for component-specific logging.
class NamedLogger {
  NamedLogger(this.name);

  final String name;

  void v(String message, {Map<String, dynamic>? context}) => 
      Logger.v(message, tag: name, context: context);
  
  void d(String message, {Map<String, dynamic>? context}) => 
      Logger.d(message, tag: name, context: context);
  
  void i(String message, {Map<String, dynamic>? context}) => 
      Logger.i(message, tag: name, context: context);
  
  void w(String message, {Object? error, Map<String, dynamic>? context}) => 
      Logger.w(message, tag: name, error: error, context: context);
  
  void e(String message, {Object? error, StackTrace? stackTrace, Map<String, dynamic>? context}) =>
      Logger.e(message, tag: name, error: error, stackTrace: stackTrace, context: context);
  
  void f(String message, {Object? error, StackTrace? stackTrace, Map<String, dynamic>? context}) =>
      Logger.f(message, tag: name, error: error, stackTrace: stackTrace, context: context);
}

/// Mixin for classes that need logging capability.
mixin Loggable {
  late final NamedLogger _logger = Logger.getLogger(runtimeType.toString());
  
  @protected
  NamedLogger get logger => _logger;
}

/// Extension to convert between LogLevel and legacy LogLevel if needed.
extension LogLevelConversion on LogLevel {
  /// Convert to a priority value compatible with LogLevel.
  int get featurePriority => switch (this) {
    LogLevel.verbose => 0,
    LogLevel.debug => 0,
    LogLevel.info => 1,
    LogLevel.warning => 2,
    LogLevel.error => 3,
    LogLevel.fatal => 3,
    LogLevel.none => 4,
  };
}

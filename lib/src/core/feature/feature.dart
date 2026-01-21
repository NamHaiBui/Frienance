/// Abstract base class for production-ready features.
/// 
/// Provides a comprehensive foundation for building resilient, observable,
/// and maintainable features in Flutter applications.
/// 
/// ## Key Capabilities:
/// - **Lifecycle Management**: Proper initialization, warmup, and disposal
/// - **Resiliency**: Retry policies with exponential backoff
/// - **Circuit Breaker**: Fault tolerance and cascading failure prevention
/// - **Health Monitoring**: Health checks and status reporting
/// - **Metrics Collection**: Performance and usage metrics
/// - **Log Buffering**: Diagnostic log capture and dump capability
/// 
/// NOTE: For parallel task execution with concurrency control, use Service.
/// 
/// ## Usage Example:
/// ```dart
/// class MyFeature extends Feature<MyFeatureConfig> {
///   MyFeature() : super(
///     name: 'MyFeature',
///     config: FeatureConfig.production,
///   );
/// 
///   @override
///   Future<void> onInitialize() async {
///      Initialize resources
///   }
/// 
///   @override
///   Future<HealthCheckResult> performHealthCheck() async {
///     Check feature health
///   }
/// 
///   @override
///   Future<void> onDispose() async {
///      Clean up resources
///   }
/// }
/// ```
library;
import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:frienance/src/core/feature/feature_config.dart';
import 'package:frienance/src/core/feature/feature_result.dart';
import 'package:frienance/src/core/feature/circuit_breaker.dart';
import 'package:frienance/src/core/feature/health_monitoring.dart';
import 'package:frienance/utils/metrics.dart';
import 'package:frienance/utils/logger.dart';

/// Lifecycle states for a feature.
enum FeatureState {
  /// Feature has been created but not initialized.
  created,
  /// Feature is currently initializing.
  initializing,
  /// Feature is initialized and ready.
  ready,
  /// Feature is warming up (pre-loading resources).
  warmingUp,
  /// Feature is warmed up and at peak performance.
  warmedUp,
  /// Feature is being disposed.
  disposing,
  /// Feature has been disposed.
  disposed,
  /// Feature encountered a fatal error.
  error,
}

/// Abstract base class for production-ready features.
/// 
/// Extend this class to create features with built-in:
/// - Lifecycle management (initialize, warmup, dispose)
/// - Retry logic with exponential backoff
/// - Circuit breaker pattern
/// - Health checks and metrics
/// - Log buffering for diagnostics
abstract class Feature {
  Feature({
    required this.name,
    FeatureConfig? config,
  }) : config = config ?? const FeatureConfig() {
    _circuitBreaker = CircuitBreaker(
      name: name,
      config: this.config.circuitBreaker,
    );
    _metrics = FeatureMetrics(name);
    _logBuffer = LogBuffer();
  }

  /// Unique name identifying this feature.
  final String name;

  /// Configuration for this feature.
  final FeatureConfig config;

  /// Current lifecycle state.
  FeatureState _state = FeatureState.created;

  /// Circuit breaker for fault tolerance.
  late final CircuitBreaker _circuitBreaker;

  /// Metrics collector.
  late final FeatureMetrics _metrics;

  /// Log buffer for diagnostics.
  late final LogBuffer _logBuffer;

  /// Initialization error, if any.
  Object? _initializationError;
  StackTrace? _initializationStackTrace;

  /// Completer for waiting on initialization.
  Completer<void>? _initCompleter;

  /// Stream controller for state changes.
  final _stateController = StreamController<FeatureState>.broadcast();

  // ============================================================
  // PUBLIC API
  // ============================================================

  /// Current feature state.
  FeatureState get state => _state;

  /// Stream of state changes.
  Stream<FeatureState> get stateChanges => _stateController.stream;

  /// Whether the feature is ready for use.
  bool get isReady => _state == FeatureState.ready || _state == FeatureState.warmedUp;

  /// Whether the feature has been disposed.
  bool get isDisposed => _state == FeatureState.disposed;

  /// Get current metrics snapshot.
  MetricsSnapshot get metricsSnapshot => _metrics.snapshot();

  /// Get circuit breaker statistics.
  CircuitBreakerStats get circuitBreakerStats => _circuitBreaker.stats;

  /// Initialize the feature.
  /// 
  /// This must be called before using the feature. It's safe to call
  /// multiple times - subsequent calls will wait for the first initialization.
  Future<FeatureResult<void>> initialize() async {
    // Already initialized or initializing
    if (_state == FeatureState.ready || _state == FeatureState.warmedUp) {
      return const Success(null);
    }
    
    // Wait for ongoing initialization
    if (_state == FeatureState.initializing && _initCompleter != null) {
      await _initCompleter!.future;
      if (_state == FeatureState.error) {
        return Failure(FeatureError.fromException(
          _initializationError!,
          stackTrace: _initializationStackTrace,
          code: FeatureError.codeInternal,
        ));
      }
      return const Success(null);
    }

    // Can't initialize if disposed
    if (_state == FeatureState.disposed) {
      return Failure(FeatureError(
        code: FeatureError.codeNotInitialized,
        message: 'Feature "$name" has been disposed and cannot be reinitialized.',
      ));
    }

    _initCompleter = Completer<void>();
    _transitionTo(FeatureState.initializing);

    try {
      await onInitialize()
          .timeout(config.timeout.initializationTimeout);
      
      _transitionTo(FeatureState.ready);
      _initCompleter!.complete();
      _logInfo('Initialized successfully');
      
      return const Success(null);
    } catch (e, st) {
      _initializationError = e;
      _initializationStackTrace = st;
      _transitionTo(FeatureState.error);
      _initCompleter!.completeError(e, st);
      _logError('Initialization failed', e, st);
      
      return Failure(FeatureError.fromException(e, stackTrace: st));
    }
  }

  /// Warm up the feature for optimal performance.
  /// 
  /// This is optional but recommended for performance-critical features.
  /// It pre-loads resources and prepares caches.
  Future<FeatureResult<void>> warmUp() async {
    if (!isReady) {
      return Failure(FeatureError(
        code: FeatureError.codeNotInitialized,
        message: 'Feature "$name" must be initialized before warming up.',
      ));
    }

    if (_state == FeatureState.warmedUp) {
      return const Success(null);
    }

    _transitionTo(FeatureState.warmingUp);

    try {
      await onWarmUp();
      _transitionTo(FeatureState.warmedUp);
      _logInfo('Warmed up successfully');
      return const Success(null);
    } catch (e, st) {
      _transitionTo(FeatureState.ready); // Fall back to ready state
      _logWarning('Warm-up failed, continuing in ready state', e);
      return Failure(FeatureError.fromException(e, stackTrace: st));
    }
  }

  /// Execute an operation with full resiliency support.
  /// 
  /// This wraps the operation with:
  /// - Circuit breaker protection
  /// - Retry logic with exponential backoff
  /// - Timeout handling
  /// - Metrics collection
  /// - Error handling
  Future<FeatureResult<T>> execute<T>(
    Future<T> Function() operation, {
    String? operationName,
    RetryConfig? retryConfig,
    Duration? timeout,
  }) async {
    // Ensure initialized
    if (!isReady) {
      final initResult = await initialize();
      if (initResult.isFailure) {
        return Failure(initResult.errorOrNull!);
      }
    }

    final effectiveRetry = retryConfig ?? config.retry;
    final effectiveTimeout = timeout ?? config.timeout.operationTimeout;
    final opName = operationName ?? 'operation';
    
    _logDebug('Starting $opName');
    final stopwatch = Stopwatch()..start();

    try {
      // Execute through circuit breaker with retry
      final result = await _executeWithRetry<T>(
        operation,
        effectiveRetry,
        effectiveTimeout,
        opName,
      );

      stopwatch.stop();
      
      if (result.isSuccess) {
        _metrics.recordSuccess(stopwatch.elapsed);
        _logDebug('Completed $opName in ${stopwatch.elapsedMilliseconds}ms');
      } else {
        _metrics.recordFailure(stopwatch.elapsed);
        _logWarning('Failed $opName after ${stopwatch.elapsedMilliseconds}ms');
      }

      return result;
    } catch (e, st) {
      stopwatch.stop();
      _metrics.recordFailure(stopwatch.elapsed);
      _logError('Uncaught exception in $opName', e, st);
      return Failure(FeatureError.fromException(e, stackTrace: st));
    }
  }

  /// Perform a health check on this feature.
  Future<HealthCheckResult> checkHealth() async {
    final stopwatch = Stopwatch()..start();
    
    try {
      // Basic state check
      if (_state == FeatureState.disposed) {
        return HealthCheckResult(
          featureName: name,
          status: HealthStatus.unhealthy,
          message: 'Feature is disposed',
          duration: stopwatch.elapsed,
        );
      }

      if (_state == FeatureState.error) {
        return HealthCheckResult(
          featureName: name,
          status: HealthStatus.unhealthy,
          message: 'Feature is in error state: $_initializationError',
          duration: stopwatch.elapsed,
        );
      }

      if (!isReady) {
        return HealthCheckResult(
          featureName: name,
          status: HealthStatus.degraded,
          message: 'Feature is not ready (state: ${_state.name})',
          duration: stopwatch.elapsed,
        );
      }

      // Circuit breaker check
      if (_circuitBreaker.state == CircuitState.open) {
        return HealthCheckResult(
          featureName: name,
          status: HealthStatus.degraded,
          message: 'Circuit breaker is open',
          details: _circuitBreaker.stats.toJson(),
          duration: stopwatch.elapsed,
        );
      }

      // Custom health check
      final result = await performHealthCheck()
          .timeout(const Duration(seconds: 10));
      
      stopwatch.stop();
      return HealthCheckResult(
        featureName: result.featureName,
        status: result.status,
        message: result.message,
        details: {
          ...result.details,
          'metrics': _metrics.snapshot().toJson(),
          'circuitBreaker': _circuitBreaker.stats.toJson(),
        },
        duration: stopwatch.elapsed,
      );
    } catch (e, st) {
      stopwatch.stop();
      _logError('Health check failed', e, st);
      return HealthCheckResult(
        featureName: name,
        status: HealthStatus.unhealthy,
        message: 'Health check threw exception: $e',
        duration: stopwatch.elapsed,
      );
    }
  }

  /// Dump diagnostic logs to a file.
  Future<File> dumpLogs(String directory) async {
    _logInfo('Dumping logs to $directory');
    return _logBuffer.dumpToFile(directory);
  }

  /// Get recent log entries.
  List<LogEntry> getRecentLogs({int count = 100}) {
    final entries = _logBuffer.getEntries();
    if (entries.length <= count) return entries;
    return entries.sublist(entries.length - count);
  }

  /// Dispose of the feature and release resources.
  Future<void> dispose() async {
    if (_state == FeatureState.disposed) return;
    if (_state == FeatureState.disposing) return;

    _transitionTo(FeatureState.disposing);
    _logInfo('Disposing feature');

    try {
      await onDispose();
      _circuitBreaker.dispose();
      _stateController.close();
      _transitionTo(FeatureState.disposed);
      _logInfo('Disposed successfully');
    } catch (e, st) {
      _logError('Error during disposal', e, st);
      _transitionTo(FeatureState.disposed);
    }
  }

  // ============================================================
  // PROTECTED API - Override in subclasses
  // ============================================================

  /// Initialize feature resources.
  /// 
  /// Override this to set up databases, network connections, caches, etc.
  @protected
  Future<void> onInitialize();

  /// Optional: Warm up the feature.
  /// 
  /// Override this to pre-load resources, warm caches, etc.
  @protected
  Future<void> onWarmUp() async {
    // Default: no warmup needed
  }

  /// Perform feature-specific health check.
  /// 
  /// Override this to check database connections, API availability, etc.
  @protected
  Future<HealthCheckResult> performHealthCheck() async {
    return HealthCheckResult(
      featureName: name,
      status: HealthStatus.healthy,
      message: 'Feature is operational',
    );
  }

  /// Dispose of feature resources.
  /// 
  /// Override this to close connections, release resources, etc.
  @protected
  Future<void> onDispose() async {
    // Default: no cleanup needed
  }

  /// Override to provide custom retry predicate.
  @protected
  bool shouldRetry(Object error, int attempt) {
    return config.retry.shouldRetry(error) && 
           attempt < config.retry.maxAttempts;
  }

  // ============================================================
  // PROTECTED LOGGING API
  // ============================================================

  @protected
  void logDebug(String message, [Map<String, dynamic>? context]) {
    _logDebug(message, context);
  }

  @protected
  void logInfo(String message, [Map<String, dynamic>? context]) {
    _logInfo(message, context);
  }

  @protected
  void logWarning(String message, [Object? error, Map<String, dynamic>? context]) {
    _logWarning(message, error, context);
  }

  @protected
  void logError(String message, Object error, [StackTrace? stackTrace, Map<String, dynamic>? context]) {
    _logError(message, error, stackTrace, context);
  }

  // ============================================================
  // PRIVATE IMPLEMENTATION
  // ============================================================

  Future<FeatureResult<T>> _executeWithRetry<T>(
    Future<T> Function() operation,
    RetryConfig retryConfig,
    Duration timeout,
    String operationName,
  ) async {
    int attempt = 0;
    Object? lastError;
    StackTrace? lastStackTrace;

    while (attempt < retryConfig.maxAttempts) {
      attempt++;

      // Execute through circuit breaker
      final result = await _circuitBreaker.execute(() async {
        return await operation().timeout(timeout);
      });

      if (result.isSuccess) {
        return result;
      }

      final error = result.errorOrNull!;
      lastError = error.cause ?? error;
      lastStackTrace = error.stackTrace;

      // Check if we should retry
      if (error.code == FeatureError.codeCircuitOpen) {
        _metrics.recordCircuitBreakerRejection();
        return result; // Don't retry circuit breaker rejections
      }

      if (!shouldRetry(lastError, attempt)) {
        return result;
      }

      // Calculate delay and wait
      final delay = retryConfig.getDelayForAttempt(attempt);
      _metrics.recordRetry();
      _logDebug('Retrying $operationName (attempt $attempt) after ${delay.inMilliseconds}ms');
      
      await retryConfig.onRetry?.call(attempt, lastError, delay);
      await Future.delayed(delay);
    }

    return Failure(FeatureError(
      code: FeatureError.codeRetryExhausted,
      message: 'Operation "$operationName" failed after $attempt attempts.',
      cause: lastError,
      stackTrace: lastStackTrace,
      context: {'attempts': attempt},
    ));
  }

  void _transitionTo(FeatureState newState) {
    if (_state == newState) return;
    final oldState = _state;
    _state = newState;
    _logDebug('State transition: ${oldState.name} -> ${newState.name}');
    _stateController.add(newState);
  }

  void _log(LogLevel level, String message, [Object? error, StackTrace? stackTrace, Map<String, dynamic>? context]) {
    if (!config.logLevel.shouldLog(level)) return;

    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      error: error,
      stackTrace: stackTrace,
      context: context ?? const {},
    );

    _logBuffer.add(entry);

    // Forward to centralized Logger
    switch (level) {
      case LogLevel.debug:
        Logger.d(message, tag: name);
      case LogLevel.info:
        Logger.i(message, tag: name);
      case LogLevel.warning:
        Logger.w(message, tag: name, error: error);
      case LogLevel.error:
        Logger.e(message, tag: name, error: error, stackTrace: stackTrace);
      default:
        break;
    }
  }

  void _logDebug(String message, [Map<String, dynamic>? context]) {
    _log(LogLevel.debug, message, null, null, context);
  }

  void _logInfo(String message, [Map<String, dynamic>? context]) {
    _log(LogLevel.info, message, null, null, context);
  }

  void _logWarning(String message, [Object? error, Map<String, dynamic>? context]) {
    _log(LogLevel.warning, message, error, null, context);
  }

  void _logError(String message, Object error, [StackTrace? stackTrace, Map<String, dynamic>? context]) {
    _log(LogLevel.error, message, error, stackTrace, context);
  }
}

/// Mixin for features that require file system operations.
mixin FileSystemFeature on Feature {
  /// Base directory for this feature's files.
  String? _baseDirectory;

  /// Get the base directory, initializing if needed.
  String get baseDirectory {
    if (_baseDirectory == null) {
      throw StateError('Base directory not set. Call setBaseDirectory() first.');
    }
    return _baseDirectory!;
  }

  /// Set the base directory for file operations.
  @protected
  void setBaseDirectory(String directory) {
    _baseDirectory = directory;
    logDebug('Base directory set to: $directory');
  }

  /// Ensure a directory exists.
  @protected
  Future<Directory> ensureDirectory(String path) async {
    final dir = Directory(path);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
      logDebug('Created directory: $path');
    }
    return dir;
  }

  /// List files in a directory matching a pattern.
  @protected
  Future<List<File>> listFiles(
    String directory, {
    List<String> extensions = const [],
  }) async {
    final dir = Directory(directory);
    if (!await dir.exists()) return [];

    final files = <File>[];
    await for (final entity in dir.list()) {
      if (entity is File) {
        if (extensions.isEmpty) {
          files.add(entity);
        } else {
          final ext = entity.path.split('.').last.toLowerCase();
          if (extensions.contains('.$ext')) {
            files.add(entity);
          }
        }
      }
    }
    return files;
  }

  /// Safely delete a file.
  @protected
  Future<bool> safeDeleteFile(String path) async {
    try {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        logDebug('Deleted file: $path');
        return true;
      }
      return false;
    } catch (e) {
      logWarning('Failed to delete file: $path', e);
      return false;
    }
  }
}

/// Mixin for features that process images.
mixin ImageProcessingFeature on Feature {
  /// Supported image extensions.
  static const List<String> supportedExtensions = ['.jpg', '.jpeg', '.png', '.webp'];

  /// Check if a file is a supported image.
  @protected
  bool isSupportedImage(String path) {
    final ext = path.split('.').last.toLowerCase();
    return supportedExtensions.contains('.$ext');
  }

  /// Get image dimensions (requires implementation).
  @protected
  Future<(int width, int height)?> getImageDimensions(String path);

  /// Validate an image file.
  @protected
  Future<FeatureResult<void>> validateImage(String path) async {
    final file = File(path);
    
    if (!await file.exists()) {
      return Failure(FeatureError(
        code: FeatureError.codeValidation,
        message: 'Image file does not exist: $path',
      ));
    }

    if (!isSupportedImage(path)) {
      return Failure(FeatureError(
        code: FeatureError.codeValidation,
        message: 'Unsupported image format. Supported: ${supportedExtensions.join(', ')}',
      ));
    }

    final size = await file.length();
    if (size == 0) {
      return Failure(FeatureError(
        code: FeatureError.codeValidation,
        message: 'Image file is empty: $path',
      ));
    }

    // Optional: Check minimum size (e.g., 10KB for a valid image)
    if (size < 10 * 1024) {
      logWarning('Image file is very small ($size bytes): $path');
    }

    return const Success(null);
  }
}

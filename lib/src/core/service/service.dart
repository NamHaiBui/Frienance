/// Abstract Service Infrastructure with Parallelism Support.
/// 
/// Services handle concurrent task execution with:
/// - Semaphore for concurrency control
/// - Task queuing and tracking
/// - Service lifecycle management
/// - Logging integration
/// 
/// NOTE: Service is INDEPENDENT of Feature. Use Feature for resiliency
/// patterns (circuit breaker, retry). Use Service for parallelism.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:frienance/utils/logger.dart';

/// Semaphore for controlling concurrent access to limited resources.
class Semaphore {
  Semaphore(this.maxConcurrent) : _available = maxConcurrent;

  final int maxConcurrent;
  int _available;
  final Queue<Completer<void>> _waitQueue = Queue<Completer<void>>();

  int get heldPermits => maxConcurrent - _available;
  int get waitingCount => _waitQueue.length;
  bool get hasAvailablePermit => _available > 0;

  /// Acquire a permit, waiting if necessary.
  Future<void> acquire() async {
    if (_available > 0) {
      _available--;
      return;
    }
    final completer = Completer<void>();
    _waitQueue.add(completer);
    await completer.future;
  }

  /// Try to acquire a permit without waiting.
  bool tryAcquire() {
    if (_available > 0) {
      _available--;
      return true;
    }
    return false;
  }

  /// Release a permit.
  void release() {
    if (_waitQueue.isNotEmpty) {
      _waitQueue.removeFirst().complete();
    } else {
      _available = (_available + 1).clamp(0, maxConcurrent);
    }
  }

  /// Execute a function with a permit.
  Future<T> withPermit<T>(Future<T> Function() action) async {
    await acquire();
    try {
      return await action();
    } finally {
      release();
    }
  }

  /// Reset the semaphore.
  void reset() {
    _available = maxConcurrent;
    while (_waitQueue.isNotEmpty) {
      _waitQueue.removeFirst().completeError(StateError('Semaphore was reset'));
    }
  }
}

/// Service configuration.
class ServiceConfig {
  const ServiceConfig({
    this.maxConcurrentTasks = 3,
    this.maxQueuedTasks = 50,
    this.taskTimeout = const Duration(minutes: 5),
  });

  final int maxConcurrentTasks;
  final int maxQueuedTasks;
  final Duration taskTimeout;

  static const ServiceConfig production = ServiceConfig();
  
  static const ServiceConfig development = ServiceConfig(
    maxConcurrentTasks: 4,
    maxQueuedTasks: 100,
  );

  ServiceConfig copyWith({
    int? maxConcurrentTasks,
    int? maxQueuedTasks,
    Duration? taskTimeout,
  }) {
    return ServiceConfig(
      maxConcurrentTasks: maxConcurrentTasks ?? this.maxConcurrentTasks,
      maxQueuedTasks: maxQueuedTasks ?? this.maxQueuedTasks,
      taskTimeout: taskTimeout ?? this.taskTimeout,
    );
  }
}

/// Service lifecycle states.
enum ServiceState {
  created,
  starting,
  running,
  paused,
  stopping,
  stopped,
  error,
}

/// Task status.
enum TaskStatus {
  queued,
  running,
  completed,
  failed,
  cancelled,
}

/// Information about a task.
class TaskInfo {
  TaskInfo({
    required this.id,
    required this.name,
    required this.createdAt,
  }) : status = TaskStatus.queued;

  final String id;
  final String name;
  final DateTime createdAt;
  TaskStatus status;
  DateTime? startedAt;
  DateTime? completedAt;
  String? error;

  Duration? get duration {
    if (startedAt == null) return null;
    return (completedAt ?? DateTime.now()).difference(startedAt!);
  }

  Duration get waitTime => (startedAt ?? DateTime.now()).difference(createdAt);

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'status': status.name,
    'createdAt': createdAt.toIso8601String(),
    'startedAt': startedAt?.toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
    'durationMs': duration?.inMilliseconds,
    'waitTimeMs': waitTime.inMilliseconds,
    'error': error,
  };
}

/// Service error for typed failures.
class ServiceError implements Exception {
  const ServiceError({
    required this.code,
    required this.message,
    this.cause,
  });

  final String code;
  final String message;
  final Object? cause;

  static const String codeNotRunning = 'SERVICE_NOT_RUNNING';
  static const String codeQueueFull = 'QUEUE_FULL';
  static const String codeStopping = 'SERVICE_STOPPING';
  static const String codeTimeout = 'TASK_TIMEOUT';
  static const String codeCancelled = 'TASK_CANCELLED';

  @override
  String toString() => 'ServiceError($code): $message';
}

/// Result type for service operations.
sealed class ServiceResult<T> {
  const ServiceResult();
  
  bool get isSuccess => this is ServiceSuccess<T>;
  bool get isFailure => this is ServiceFailure<T>;
  
  T? get valueOrNull => switch (this) {
    ServiceSuccess<T>(:final value) => value,
    ServiceFailure<T>() => null,
  };
  
  ServiceError? get errorOrNull => switch (this) {
    ServiceSuccess<T>() => null,
    ServiceFailure<T>(:final error) => error,
  };
}

class ServiceSuccess<T> extends ServiceResult<T> {
  const ServiceSuccess(this.value);
  final T value;
}

class ServiceFailure<T> extends ServiceResult<T> {
  const ServiceFailure(this.error);
  final ServiceError error;
}

/// Abstract base class for services with parallelism support.
abstract class Service {
  Service({
    required this.name,
    ServiceConfig? config,
  }) : config = config ?? const ServiceConfig() {
    _semaphore = Semaphore(this.config.maxConcurrentTasks);
    _metrics = ServiceMetrics(name);
    _logger = Logger.getLogger(name);
  }

  final String name;
  final ServiceConfig config;

  late final Semaphore _semaphore;
  late final ServiceMetrics _metrics;
  late final NamedLogger _logger;

  ServiceState _state = ServiceState.created;
  final Map<String, TaskInfo> _tasks = {};
  final Queue<_QueuedTask> _taskQueue = Queue<_QueuedTask>();
  final _stateController = StreamController<ServiceState>.broadcast();
  int _taskIdCounter = 0;

  // ============================================================
  // PUBLIC API
  // ============================================================

  ServiceState get state => _state;
  Stream<ServiceState> get stateChanges => _stateController.stream;
  bool get isRunning => _state == ServiceState.running;
  bool get isAcceptingTasks => 
      _state == ServiceState.running && 
      _taskQueue.length < config.maxQueuedTasks;

  int get queuedTaskCount => _taskQueue.length;
  ServiceMetricsSnapshot get metrics => _metrics.snapshot();
  SemaphoreStatus get semaphoreStatus => SemaphoreStatus(
    maxConcurrent: _semaphore.maxConcurrent,
    heldPermits: _semaphore.heldPermits,
    waitingCount: _semaphore.waitingCount,
  );
  List<TaskInfo> get tasks => _tasks.values.toList();
  TaskInfo? getTask(String taskId) => _tasks[taskId];

  /// Start the service.
  Future<ServiceResult<void>> start() async {
    if (_state == ServiceState.running) {
      return const ServiceSuccess(null);
    }
    if (_state == ServiceState.stopping) {
      return const ServiceFailure(ServiceError(
        code: ServiceError.codeStopping,
        message: 'Service is currently stopping',
      ));
    }

    _transitionTo(ServiceState.starting);
    _logger.i('Starting service');

    try {
      await onStart();
      _transitionTo(ServiceState.running);
      _logger.i('Service started');
      return const ServiceSuccess(null);
    } catch (e, st) {
      _transitionTo(ServiceState.error);
      _logger.e('Failed to start service', error: e, stackTrace: st);
      return ServiceFailure(ServiceError(
        code: 'START_FAILED',
        message: 'Failed to start service: $e',
        cause: e,
      ));
    }
  }

  /// Stop the service gracefully.
  Future<ServiceResult<void>> stop() async {
    if (_state == ServiceState.stopped) {
      return const ServiceSuccess(null);
    }

    _transitionTo(ServiceState.stopping);
    _logger.i('Stopping service');

    // Cancel queued tasks
    while (_taskQueue.isNotEmpty) {
      final task = _taskQueue.removeFirst();
      task.completer.completeError(const ServiceError(
        code: ServiceError.codeCancelled,
        message: 'Service is stopping',
      ));
      _updateTaskStatus(task.taskId, TaskStatus.cancelled);
    }

    try {
      await onStop();
      _transitionTo(ServiceState.stopped);
      _semaphore.reset();
      _logger.i('Service stopped');
      return const ServiceSuccess(null);
    } catch (e, st) {
      _logger.e('Error during stop', error: e, stackTrace: st);
      _transitionTo(ServiceState.stopped);
      return ServiceFailure(ServiceError(
        code: 'STOP_FAILED',
        message: 'Error during stop: $e',
        cause: e,
      ));
    }
  }

  /// Pause (stop accepting new tasks).
  void pause() {
    if (_state == ServiceState.running) {
      _transitionTo(ServiceState.paused);
      _logger.i('Service paused');
    }
  }

  /// Resume accepting tasks.
  void resume() {
    if (_state == ServiceState.paused) {
      _transitionTo(ServiceState.running);
      _logger.i('Service resumed');
      _processQueue();
    }
  }

  /// Submit a task for processing.
  Future<ServiceResult<T>> submitTask<T>({
    required String taskName,
    required Future<T> Function() processor,
    Duration? timeout,
  }) async {
    if (!isAcceptingTasks) {
      return ServiceFailure(ServiceError(
        code: _state == ServiceState.running 
            ? ServiceError.codeQueueFull 
            : ServiceError.codeNotRunning,
        message: 'Service is not accepting tasks (state: ${_state.name})',
      ));
    }

    final taskId = _generateTaskId();
    final task = TaskInfo(id: taskId, name: taskName, createdAt: DateTime.now());
    _tasks[taskId] = task;

    final completer = Completer<T>();
    _taskQueue.add(_QueuedTask(
      taskId: taskId,
      processor: processor,
      completer: completer,
      timeout: timeout ?? config.taskTimeout,
    ));
    _metrics.recordTaskQueued();
    _logger.d('Task queued: $taskId ($taskName)');

    _processQueue();

    try {
      final result = await completer.future;
      return ServiceSuccess(result);
    } on ServiceError catch (e) {
      return ServiceFailure(e);
    } catch (e) {
      return ServiceFailure(ServiceError(
        code: 'TASK_FAILED',
        message: 'Task failed: $e',
        cause: e,
      ));
    }
  }

  /// Dispose service resources.
  Future<void> dispose() async {
    if (_state != ServiceState.stopped) {
      await stop();
    }
    await _stateController.close();
  }

  // ============================================================
  // PROTECTED API
  // ============================================================

  /// Called when service starts. Override for initialization.
  @protected
  Future<void> onStart() async {}

  /// Called when service stops. Override for cleanup.
  @protected
  Future<void> onStop() async {}

  /// Logging helpers.
  @protected
  void logDebug(String message) => _logger.d(message);
  @protected
  void logInfo(String message) => _logger.i(message);
  @protected
  void logWarning(String message, [Object? error]) => _logger.w(message, error: error);
  @protected
  void logError(String message, Object error, [StackTrace? st]) => 
      _logger.e(message, error: error, stackTrace: st);

  // ============================================================
  // PRIVATE
  // ============================================================

  String _generateTaskId() => '${name}_${++_taskIdCounter}';

  void _transitionTo(ServiceState newState) {
    if (_state == newState) return;
    _state = newState;
    _stateController.add(newState);
  }

  void _processQueue() {
    if (_state != ServiceState.running) return;

    while (_taskQueue.isNotEmpty && _semaphore.tryAcquire()) {
      final task = _taskQueue.removeFirst();
      _executeTask(task);
    }
  }

  Future<void> _executeTask(_QueuedTask task) async {
    final taskInfo = _tasks[task.taskId];
    if (taskInfo == null) {
      _semaphore.release();
      return;
    }

    taskInfo.status = TaskStatus.running;
    taskInfo.startedAt = DateTime.now();
    _metrics.recordTaskStarted();
    _logger.d('Task started: ${task.taskId}');

    try {
      final result = await task.processor().timeout(task.timeout);
      taskInfo.status = TaskStatus.completed;
      taskInfo.completedAt = DateTime.now();
      _metrics.recordTaskCompleted(taskInfo.duration!);
      _logger.d('Task completed: ${task.taskId} (${taskInfo.duration!.inMilliseconds}ms)');
      task.completer.complete(result);
    } catch (e, st) {
      taskInfo.status = TaskStatus.failed;
      taskInfo.completedAt = DateTime.now();
      taskInfo.error = e.toString();
      _metrics.recordTaskFailed(taskInfo.duration ?? Duration.zero);
      _logger.e('Task failed: ${task.taskId}', error: e, stackTrace: st);
      task.completer.completeError(e, st);
    } finally {
      _semaphore.release();
      _processQueue();
    }
  }

  void _updateTaskStatus(String taskId, TaskStatus status) {
    final task = _tasks[taskId];
    if (task != null) {
      task.status = status;
      if (status == TaskStatus.cancelled) {
        task.completedAt = DateTime.now();
      }
    }
  }
}

/// Internal queued task.
class _QueuedTask<T> {
  _QueuedTask({
    required this.taskId,
    required this.processor,
    required this.completer,
    required this.timeout,
  });

  final String taskId;
  final Future<T> Function() processor;
  final Completer<T> completer;
  final Duration timeout;
}

/// Service metrics - lightweight for mobile.
class ServiceMetrics {
  ServiceMetrics(this.serviceName);

  final String serviceName;
  int _totalTasks = 0;
  int _completedTasks = 0;
  int _failedTasks = 0;
  int _queuedTasks = 0;
  int _peakQueueSize = 0;
  int _totalDurationMs = 0;
  int _maxDurationMs = 0;

  void recordTaskQueued() {
    _queuedTasks++;
    _totalTasks++;
    if (_queuedTasks > _peakQueueSize) _peakQueueSize = _queuedTasks;
  }

  void recordTaskStarted() {
    if (_queuedTasks > 0) _queuedTasks--;
  }

  void recordTaskCompleted(Duration duration) {
    _completedTasks++;
    _recordDuration(duration);
  }

  void recordTaskFailed(Duration duration) {
    _failedTasks++;
    _recordDuration(duration);
  }

  void _recordDuration(Duration duration) {
    final ms = duration.inMilliseconds;
    _totalDurationMs += ms;
    if (ms > _maxDurationMs) _maxDurationMs = ms;
  }

  ServiceMetricsSnapshot snapshot() {
    final processed = _completedTasks + _failedTasks;
    return ServiceMetricsSnapshot(
      serviceName: serviceName,
      totalTasks: _totalTasks,
      completedTasks: _completedTasks,
      failedTasks: _failedTasks,
      currentQueueSize: _queuedTasks,
      peakQueueSize: _peakQueueSize,
      averageDurationMs: processed > 0 ? _totalDurationMs / processed : 0.0,
      maxDurationMs: _maxDurationMs,
    );
  }
}

/// Snapshot of service metrics.
class ServiceMetricsSnapshot {
  const ServiceMetricsSnapshot({
    required this.serviceName,
    required this.totalTasks,
    required this.completedTasks,
    required this.failedTasks,
    required this.currentQueueSize,
    required this.peakQueueSize,
    required this.averageDurationMs,
    required this.maxDurationMs,
  });

  final String serviceName;
  final int totalTasks;
  final int completedTasks;
  final int failedTasks;
  final int currentQueueSize;
  final int peakQueueSize;
  final double averageDurationMs;
  final int maxDurationMs;

  double get successRate {
    final processed = completedTasks + failedTasks;
    if (processed == 0) return 100.0;
    return (completedTasks / processed) * 100;
  }

  Map<String, dynamic> toJson() => {
    'serviceName': serviceName,
    'totalTasks': totalTasks,
    'completedTasks': completedTasks,
    'failedTasks': failedTasks,
    'currentQueueSize': currentQueueSize,
    'peakQueueSize': peakQueueSize,
    'successRate': '${successRate.toStringAsFixed(1)}%',
    'averageDurationMs': averageDurationMs.toStringAsFixed(0),
    'maxDurationMs': maxDurationMs,
  };
}

/// Semaphore status.
class SemaphoreStatus {
  const SemaphoreStatus({
    required this.maxConcurrent,
    required this.heldPermits,
    required this.waitingCount,
  });

  final int maxConcurrent;
  final int heldPermits;
  final int waitingCount;
  int get availablePermits => maxConcurrent - heldPermits;

  Map<String, dynamic> toJson() => {
    'maxConcurrent': maxConcurrent,
    'heldPermits': heldPermits,
    'availablePermits': availablePermits,
    'waitingCount': waitingCount,
  };
}

/// Mixin for temporary directory management.
mixin TemporaryDirectoryService on Service {
  @protected
  Future<Directory> createTempDirectory(String taskId) async {
    final workDir = Directory('${Directory.systemTemp.path}/$name/$taskId');
    await workDir.create(recursive: true);
    logDebug('Created temp directory: ${workDir.path}');
    return workDir;
  }

  @protected
  Future<void> cleanupTempDirectory(
    Directory workDir, {
    List<String> preserveFiles = const [],
    String? movePreservedTo,
  }) async {
    if (!await workDir.exists()) return;

    try {
      if (movePreservedTo != null && preserveFiles.isNotEmpty) {
        final preserveDir = Directory(movePreservedTo);
        await preserveDir.create(recursive: true);
        for (final fileName in preserveFiles) {
          final file = File('${workDir.path}/$fileName');
          if (await file.exists()) {
            await file.copy('${preserveDir.path}/$fileName');
          }
        }
      }
      await workDir.delete(recursive: true);
      logDebug('Cleaned up temp directory: ${workDir.path}');
    } catch (e) {
      logWarning('Failed to cleanup temp directory', e);
    }
  }
}

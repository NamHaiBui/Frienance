/// Circuit breaker implementation for fault tolerance.
/// 
/// Implements the circuit breaker pattern to prevent cascading failures
/// and allow systems to recover gracefully from errors.
library;

import 'dart:async';

import 'package:frienance/src/core/feature/feature_config.dart';
import 'package:frienance/src/core/feature/feature_result.dart';

/// Circuit breaker that wraps operations and protects against cascading failures.
class CircuitBreaker {
  CircuitBreaker({
    required this.name,
    CircuitBreakerConfig? config,
  }) : config = config ?? const CircuitBreakerConfig();

  /// Name of this circuit breaker for logging and metrics.
  final String name;

  /// Configuration for this circuit breaker.
  final CircuitBreakerConfig config;

  /// Current state of the circuit.
  CircuitState _state = CircuitState.closed;

  /// Number of consecutive failures in closed state.
  int _failureCount = 0;

  /// Number of consecutive successes in half-open state.
  int _successCount = 0;

  /// Number of ongoing requests in half-open state.
  int _halfOpenRequests = 0;

  /// Time when the circuit was opened.
  DateTime? _openedAt;

  /// History of recent operations for debugging.
  final List<CircuitBreakerEvent> _eventHistory = [];

  /// Maximum events to keep in history.
  static const int _maxHistorySize = 100;

  /// Stream controller for state changes.
  final _stateController = StreamController<CircuitState>.broadcast();

  /// Stream of circuit state changes.
  Stream<CircuitState> get stateChanges => _stateController.stream;

  /// Current circuit state.
  CircuitState get state => _state;

  /// Whether the circuit is currently allowing requests.
  bool get isAllowingRequests {
    _checkStateTransition();
    return _state != CircuitState.open;
  }

  /// Get recent event history for debugging.
  List<CircuitBreakerEvent> get eventHistory => List.unmodifiable(_eventHistory);

  /// Get circuit breaker statistics.
  CircuitBreakerStats get stats => CircuitBreakerStats(
    name: name,
    state: _state,
    failureCount: _failureCount,
    successCount: _successCount,
    openedAt: _openedAt,
    eventHistory: _eventHistory,
  );

  /// Execute an operation through the circuit breaker.
  Future<FeatureResult<T>> execute<T>(Future<T> Function() operation) async {
    _checkStateTransition();

    switch (_state) {
      case CircuitState.open:
        _recordEvent(CircuitBreakerEventType.rejected);
        return Failure(FeatureError(
          code: FeatureError.codeCircuitOpen,
          message: 'Circuit breaker "$name" is open. '
              'Retry after ${_remainingOpenDuration?.inSeconds ?? 0}s.',
          context: {
            'circuitName': name,
            'openedAt': _openedAt?.toIso8601String(),
            'remainingSeconds': _remainingOpenDuration?.inSeconds,
          },
          recoverable: true,
        ));

      case CircuitState.halfOpen:
        if (_halfOpenRequests >= config.halfOpenMaxAttempts) {
          _recordEvent(CircuitBreakerEventType.rejected);
          return Failure(FeatureError(
            code: FeatureError.codeCircuitOpen,
            message: 'Circuit breaker "$name" is testing recovery. '
                'Max concurrent requests reached.',
            context: {
              'circuitName': name,
              'halfOpenRequests': _halfOpenRequests,
            },
            recoverable: true,
          ));
        }
        _halfOpenRequests++;
        break;

      case CircuitState.closed:
        break;
    }

    try {
      final result = await operation();
      _recordSuccess();
      return Success(result);
    } catch (e, st) {
      _recordFailure();
      return Failure(FeatureError.fromException(e, stackTrace: st));
    }
  }

  /// Execute an operation that returns a FeatureResult.
  Future<FeatureResult<T>> executeResult<T>(
    Future<FeatureResult<T>> Function() operation,
  ) async {
    _checkStateTransition();

    switch (_state) {
      case CircuitState.open:
        _recordEvent(CircuitBreakerEventType.rejected);
        return Failure(FeatureError(
          code: FeatureError.codeCircuitOpen,
          message: 'Circuit breaker "$name" is open.',
          recoverable: true,
        ));

      case CircuitState.halfOpen:
        if (_halfOpenRequests >= config.halfOpenMaxAttempts) {
          _recordEvent(CircuitBreakerEventType.rejected);
          return Failure(FeatureError(
            code: FeatureError.codeCircuitOpen,
            message: 'Circuit breaker "$name" half-open capacity reached.',
            recoverable: true,
          ));
        }
        _halfOpenRequests++;
        break;

      case CircuitState.closed:
        break;
    }

    try {
      final result = await operation();
      if (result.isSuccess) {
        _recordSuccess();
      } else {
        _recordFailure();
      }
      return result;
    } catch (e, st) {
      _recordFailure();
      return Failure(FeatureError.fromException(e, stackTrace: st));
    }
  }

  /// Manually open the circuit (for emergencies or testing).
  void forceOpen() {
    _transitionTo(CircuitState.open);
  }

  /// Manually close the circuit (for recovery or testing).
  void forceClose() {
    _transitionTo(CircuitState.closed);
  }

  /// Reset the circuit breaker to its initial state.
  void reset() {
    _state = CircuitState.closed;
    _failureCount = 0;
    _successCount = 0;
    _halfOpenRequests = 0;
    _openedAt = null;
    _recordEvent(CircuitBreakerEventType.reset);
    _stateController.add(_state);
  }

  /// Dispose of resources.
  void dispose() {
    _stateController.close();
  }

  void _checkStateTransition() {
    if (_state == CircuitState.open && _shouldTransitionToHalfOpen()) {
      _transitionTo(CircuitState.halfOpen);
    }
  }

  bool _shouldTransitionToHalfOpen() {
    if (_openedAt == null) return false;
    return DateTime.now().difference(_openedAt!) >= config.timeout;
  }

  Duration? get _remainingOpenDuration {
    if (_openedAt == null || _state != CircuitState.open) return null;
    final elapsed = DateTime.now().difference(_openedAt!);
    final remaining = config.timeout - elapsed;
    return remaining.isNegative ? Duration.zero : remaining;
  }

  void _recordSuccess() {
    _recordEvent(CircuitBreakerEventType.success);

    switch (_state) {
      case CircuitState.closed:
        _failureCount = 0;
        break;

      case CircuitState.halfOpen:
        _halfOpenRequests--;
        _successCount++;
        if (_successCount >= config.successThreshold) {
          _transitionTo(CircuitState.closed);
        }
        break;

      case CircuitState.open:
        // Shouldn't happen, but handle gracefully
        break;
    }
  }

  void _recordFailure() {
    _recordEvent(CircuitBreakerEventType.failure);

    switch (_state) {
      case CircuitState.closed:
        _failureCount++;
        if (_failureCount >= config.failureThreshold) {
          _transitionTo(CircuitState.open);
        }
        break;

      case CircuitState.halfOpen:
        _halfOpenRequests--;
        _transitionTo(CircuitState.open);
        break;

      case CircuitState.open:
        // Shouldn't happen
        break;
    }
  }

  void _transitionTo(CircuitState newState) {
    if (_state == newState) return;

    final oldState = _state;
    _state = newState;

    switch (newState) {
      case CircuitState.open:
        _openedAt = DateTime.now();
        _successCount = 0;
        _halfOpenRequests = 0;
        _recordEvent(CircuitBreakerEventType.opened);
        break;

      case CircuitState.halfOpen:
        _successCount = 0;
        _halfOpenRequests = 0;
        _recordEvent(CircuitBreakerEventType.halfOpened);
        break;

      case CircuitState.closed:
        _failureCount = 0;
        _successCount = 0;
        _openedAt = null;
        _recordEvent(CircuitBreakerEventType.closed);
        break;
    }

    config.onStateChange?.call(oldState, newState);
    _stateController.add(newState);
  }

  void _recordEvent(CircuitBreakerEventType type) {
    _eventHistory.add(CircuitBreakerEvent(
      type: type,
      timestamp: DateTime.now(),
      state: _state,
    ));

    // Trim history if too large
    while (_eventHistory.length > _maxHistorySize) {
      _eventHistory.removeAt(0);
    }
  }
}

/// Types of circuit breaker events.
enum CircuitBreakerEventType {
  success,
  failure,
  rejected,
  opened,
  halfOpened,
  closed,
  reset,
}

/// Record of a circuit breaker event.
class CircuitBreakerEvent {
  const CircuitBreakerEvent({
    required this.type,
    required this.timestamp,
    required this.state,
  });

  final CircuitBreakerEventType type;
  final DateTime timestamp;
  final CircuitState state;

  @override
  String toString() => '[$timestamp] $type (state: $state)';
}

/// Statistics for a circuit breaker.
class CircuitBreakerStats {
  const CircuitBreakerStats({
    required this.name,
    required this.state,
    required this.failureCount,
    required this.successCount,
    this.openedAt,
    this.eventHistory = const [],
  });

  final String name;
  final CircuitState state;
  final int failureCount;
  final int successCount;
  final DateTime? openedAt;
  final List<CircuitBreakerEvent> eventHistory;

  Map<String, dynamic> toJson() => {
    'name': name,
    'state': state.name,
    'failureCount': failureCount,
    'successCount': successCount,
    'openedAt': openedAt?.toIso8601String(),
    'recentEvents': eventHistory.take(10).map((e) => e.toString()).toList(),
  };

  @override
  String toString() => 'CircuitBreaker($name): $state '
      '(failures: $failureCount, successes: $successCount)';
}

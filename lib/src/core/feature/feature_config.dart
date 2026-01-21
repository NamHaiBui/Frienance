/// Configuration classes for production-ready features.
/// 
/// Provides type-safe configuration for retry policies, circuit breakers,
/// timeouts, and resource management.
library;

import 'dart:async';

import 'package:frienance/utils/logger.dart';

/// Retry policy configuration for resilient operations.
class RetryConfig {
  const RetryConfig({
    this.maxAttempts = 3,
    this.initialDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 30),
    this.backoffMultiplier = 2.0,
    this.retryableExceptions = const <Type>{},
    this.onRetry,
  });

  /// Maximum number of retry attempts (including the initial attempt).
  final int maxAttempts;

  /// Initial delay before the first retry.
  final Duration initialDelay;

  /// Maximum delay between retries (caps exponential backoff).
  final Duration maxDelay;

  /// Multiplier for exponential backoff calculation.
  final double backoffMultiplier;

  /// Set of exception types that should trigger a retry.
  /// Empty set means retry on all exceptions.
  final Set<Type> retryableExceptions;

  /// Optional callback invoked before each retry attempt.
  final FutureOr<void> Function(int attempt, Object error, Duration delay)? onRetry;

  /// Calculate delay for a given attempt using exponential backoff.
  Duration getDelayForAttempt(int attempt) {
    if (attempt <= 1) return Duration.zero;
    
    final exponentialDelay = initialDelay.inMilliseconds * 
        (backoffMultiplier * (attempt - 1));
    final cappedDelay = exponentialDelay.clamp(
      initialDelay.inMilliseconds.toDouble(),
      maxDelay.inMilliseconds.toDouble(),
    );
    
    return Duration(milliseconds: cappedDelay.toInt());
  }

  /// Check if an exception should trigger a retry.
  bool shouldRetry(Object error) {
    if (retryableExceptions.isEmpty) return true;
    return retryableExceptions.contains(error.runtimeType);
  }

  /// No retry configuration.
  static const RetryConfig none = RetryConfig(maxAttempts: 1);

  /// Aggressive retry for critical operations.
  static const RetryConfig aggressive = RetryConfig(
    maxAttempts: 5,
    initialDelay: Duration(milliseconds: 200),
    maxDelay: Duration(seconds: 10),
    backoffMultiplier: 1.5,
  );

  RetryConfig copyWith({
    int? maxAttempts,
    Duration? initialDelay,
    Duration? maxDelay,
    double? backoffMultiplier,
    Set<Type>? retryableExceptions,
    FutureOr<void> Function(int, Object, Duration)? onRetry,
  }) {
    return RetryConfig(
      maxAttempts: maxAttempts ?? this.maxAttempts,
      initialDelay: initialDelay ?? this.initialDelay,
      maxDelay: maxDelay ?? this.maxDelay,
      backoffMultiplier: backoffMultiplier ?? this.backoffMultiplier,
      retryableExceptions: retryableExceptions ?? this.retryableExceptions,
      onRetry: onRetry ?? this.onRetry,
    );
  }
}

/// Circuit breaker states.
enum CircuitState {
  /// Circuit is closed - requests flow normally.
  closed,
  
  /// Circuit is open - requests are rejected immediately.
  open,
  
  /// Circuit is testing - limited requests allowed to test recovery.
  halfOpen,
}

/// Circuit breaker configuration for fault tolerance.
class CircuitBreakerConfig {
  const CircuitBreakerConfig({
    this.failureThreshold = 5,
    this.successThreshold = 2,
    this.timeout = const Duration(seconds: 30),
    this.halfOpenMaxAttempts = 3,
    this.onStateChange,
  });

  /// Number of consecutive failures before opening the circuit.
  final int failureThreshold;

  /// Number of consecutive successes in half-open state before closing.
  final int successThreshold;

  /// Duration the circuit stays open before transitioning to half-open.
  final Duration timeout;

  /// Maximum concurrent requests allowed in half-open state.
  final int halfOpenMaxAttempts;

  /// Callback invoked when circuit state changes.
  final void Function(CircuitState oldState, CircuitState newState)? onStateChange;

  /// Disabled circuit breaker (always closed).
  static const CircuitBreakerConfig disabled = CircuitBreakerConfig(
    failureThreshold: 999999,
    timeout: Duration(days: 365),
  );

  /// Sensitive circuit breaker for critical paths.
  static const CircuitBreakerConfig sensitive = CircuitBreakerConfig(
    failureThreshold: 3,
    successThreshold: 3,
    timeout: Duration(seconds: 60),
    halfOpenMaxAttempts: 1,
  );

  CircuitBreakerConfig copyWith({
    int? failureThreshold,
    int? successThreshold,
    Duration? timeout,
    int? halfOpenMaxAttempts,
    void Function(CircuitState, CircuitState)? onStateChange,
  }) {
    return CircuitBreakerConfig(
      failureThreshold: failureThreshold ?? this.failureThreshold,
      successThreshold: successThreshold ?? this.successThreshold,
      timeout: timeout ?? this.timeout,
      halfOpenMaxAttempts: halfOpenMaxAttempts ?? this.halfOpenMaxAttempts,
      onStateChange: onStateChange ?? this.onStateChange,
    );
  }
}

/// Timeout configuration for operations.
class TimeoutConfig {
  const TimeoutConfig({
    this.operationTimeout = const Duration(seconds: 30),
    this.initializationTimeout = const Duration(seconds: 60),
    this.shutdownTimeout = const Duration(seconds: 10),
  });

  /// Timeout for individual operations.
  final Duration operationTimeout;

  /// Timeout for feature initialization.
  final Duration initializationTimeout;

  /// Timeout for graceful shutdown.
  final Duration shutdownTimeout;

  /// No timeout (use with caution).
  static const TimeoutConfig none = TimeoutConfig(
    operationTimeout: Duration(days: 365),
    initializationTimeout: Duration(days: 365),
    shutdownTimeout: Duration(days: 365),
  );

  /// Quick timeout for responsive UIs.
  static const TimeoutConfig quick = TimeoutConfig(
    operationTimeout: Duration(seconds: 10),
    initializationTimeout: Duration(seconds: 30),
    shutdownTimeout: Duration(seconds: 5),
  );

  TimeoutConfig copyWith({
    Duration? operationTimeout,
    Duration? initializationTimeout,
    Duration? shutdownTimeout,
  }) {
    return TimeoutConfig(
      operationTimeout: operationTimeout ?? this.operationTimeout,
      initializationTimeout: initializationTimeout ?? this.initializationTimeout,
      shutdownTimeout: shutdownTimeout ?? this.shutdownTimeout,
    );
  }
}

/// Combined configuration for a feature.
/// 
class FeatureConfig {
  const FeatureConfig({
    this.retry = const RetryConfig(),
    this.circuitBreaker = const CircuitBreakerConfig(),
    this.timeout = const TimeoutConfig(),
    this.enableMetrics = true,
    this.enableHealthChecks = true,
    this.logLevel = LogLevel.info,
  });

  final RetryConfig retry;
  final CircuitBreakerConfig circuitBreaker;
  final TimeoutConfig timeout;
  
  /// Whether to collect metrics for this feature.
  final bool enableMetrics;
  
  /// Whether to include this feature in health checks.
  final bool enableHealthChecks;
  
  /// Minimum log level for this feature.
  final LogLevel logLevel;

  /// Default production configuration.
  static const FeatureConfig production = FeatureConfig(
    retry: RetryConfig(),
    circuitBreaker: CircuitBreakerConfig(),
    timeout: TimeoutConfig(),
    enableMetrics: true,
    enableHealthChecks: true,
    logLevel: LogLevel.warning,
  );

  /// Development configuration with verbose logging.
  static const FeatureConfig development = FeatureConfig(
    retry: RetryConfig.none,
    circuitBreaker: CircuitBreakerConfig.disabled,
    timeout: TimeoutConfig.none,
    enableMetrics: true,
    enableHealthChecks: true,
    logLevel: LogLevel.debug,
  );

  FeatureConfig copyWith({
    RetryConfig? retry,
    CircuitBreakerConfig? circuitBreaker,
    TimeoutConfig? timeout,
    bool? enableMetrics,
    bool? enableHealthChecks,
    LogLevel? logLevel,
  }) {
    return FeatureConfig(
      retry: retry ?? this.retry,
      circuitBreaker: circuitBreaker ?? this.circuitBreaker,
      timeout: timeout ?? this.timeout,
      enableMetrics: enableMetrics ?? this.enableMetrics,
      enableHealthChecks: enableHealthChecks ?? this.enableHealthChecks,
      logLevel: logLevel ?? this.logLevel,
    );
  }
}

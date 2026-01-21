

class FeatureMetrics {

  /// Metrics collector for feature operations.
  /// 
  /// Lightweight metrics for mobile - tracks success/failure counts
  /// and average duration. No server-style percentile tracking.

  FeatureMetrics(this.featureName);

  final String featureName;

  int _totalOperations = 0;
  int _successfulOperations = 0;
  int _failedOperations = 0;
  int _retriedOperations = 0;
  int _circuitBreakerRejections = 0;

  /// Rolling sum for average calculation (avoids storing samples).
  int _totalDurationMs = 0;
  int _maxDurationMs = 0;

  int get totalOperations => _totalOperations;
  int get successfulOperations => _successfulOperations;
  int get failedOperations => _failedOperations;
  int get retriedOperations => _retriedOperations;
  int get circuitBreakerRejections => _circuitBreakerRejections;
  int get maxDurationMs => _maxDurationMs;

  /// Success rate as a percentage (0-100).
  double get successRate {
    if (_totalOperations == 0) return 100.0;
    return (_successfulOperations / _totalOperations) * 100;
  }

  /// Average operation duration in milliseconds.
  double get averageDurationMs {
    if (_totalOperations == 0) return 0.0;
    return _totalDurationMs / _totalOperations;
  }

  /// Record a successful operation.
  void recordSuccess(Duration duration) {
    _totalOperations++;
    _successfulOperations++;
    _recordDuration(duration);
  }

  /// Record a failed operation.
  void recordFailure(Duration duration) {
    _totalOperations++;
    _failedOperations++;
    _recordDuration(duration);
  }

  /// Record a retry attempt.
  void recordRetry() {
    _retriedOperations++;
  }

  /// Record a circuit breaker rejection.
  void recordCircuitBreakerRejection() {
    _circuitBreakerRejections++;
  }

  /// Reset all metrics.
  void reset() {
    _totalOperations = 0;
    _successfulOperations = 0;
    _failedOperations = 0;
    _retriedOperations = 0;
    _circuitBreakerRejections = 0;
    _totalDurationMs = 0;
    _maxDurationMs = 0;
  }

  void _recordDuration(Duration duration) {
    final ms = duration.inMilliseconds;
    _totalDurationMs += ms;
    if (ms > _maxDurationMs) _maxDurationMs = ms;
  }

  /// Get a snapshot of all metrics.
  MetricsSnapshot snapshot() => MetricsSnapshot(
    featureName: featureName,
    totalOperations: _totalOperations,
    successfulOperations: _successfulOperations,
    failedOperations: _failedOperations,
    retriedOperations: _retriedOperations,
    circuitBreakerRejections: _circuitBreakerRejections,
    successRate: successRate,
    averageDurationMs: averageDurationMs,
    maxDurationMs: _maxDurationMs,
    timestamp: DateTime.now(),
  );
}

/// Immutable snapshot of metrics at a point in time.
class MetricsSnapshot {
  const MetricsSnapshot({
    required this.featureName,
    required this.totalOperations,
    required this.successfulOperations,
    required this.failedOperations,
    required this.retriedOperations,
    required this.circuitBreakerRejections,
    required this.successRate,
    required this.averageDurationMs,
    required this.maxDurationMs,
    required this.timestamp,
  });

  final String featureName;
  final int totalOperations;
  final int successfulOperations;
  final int failedOperations;
  final int retriedOperations;
  final int circuitBreakerRejections;
  final double successRate;
  final double averageDurationMs;
  final int maxDurationMs;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
    'feature': featureName,
    'totalOperations': totalOperations,
    'successfulOperations': successfulOperations,
    'failedOperations': failedOperations,
    'retriedOperations': retriedOperations,
    'circuitBreakerRejections': circuitBreakerRejections,
    'successRate': '${successRate.toStringAsFixed(1)}%',
    'averageDurationMs': averageDurationMs.toStringAsFixed(0),
    'maxDurationMs': maxDurationMs,
    'timestamp': timestamp.toIso8601String(),
  };

  @override
  String toString() => 'Metrics($featureName): '
      '$totalOperations ops, ${successRate.toStringAsFixed(1)}% success, '
      '${averageDurationMs.toStringAsFixed(0)}ms avg';
}

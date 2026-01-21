/// Health monitoring and metrics for features.
/// 
/// Provides health checks, metrics collection, and diagnostics
/// for production monitoring and observability.
library;
/// Health status of a feature or component.
enum HealthStatus {
  /// Component is functioning normally.
  healthy,  
  /// Component is functioning with degraded performance.
  degraded,
  /// Component is not functioning.
  unhealthy,  
  /// Health status is unknown (e.g., not yet checked).
  unknown,
}

/// Health check result for a feature.
class HealthCheckResult {
  HealthCheckResult({
    required this.featureName,
    required this.status,
    this.message,
    this.details = const {},
    DateTime? timestamp,
    this.duration,
  }) : timestamp = timestamp ?? DateTime.now();

  final String featureName;
  final HealthStatus status;
  final String? message;
  final Map<String, dynamic> details;
  final DateTime timestamp;
  final Duration? duration;

  bool get isHealthy => status == HealthStatus.healthy;
  bool get isDegraded => status == HealthStatus.degraded;
  bool get isUnhealthy => status == HealthStatus.unhealthy;

  Map<String, dynamic> toJson() => {
    'feature': featureName,
    'status': status.name,
    'message': message,
    'details': details,
    'timestamp': timestamp.toIso8601String(),
    'durationMs': duration?.inMilliseconds,
  };

  @override
  String toString() => 'HealthCheck($featureName): $status${message != null ? ' - $message' : ''}';
}

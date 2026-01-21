/// Core feature infrastructure for production-ready Flutter applications.
/// 
/// This library provides a comprehensive foundation for building resilient,
/// observable, and maintainable features.
/// 
/// ## Quick Start
/// 
/// ```dart
/// import 'package:frienance/src/core/feature/feature.dart';
/// 
/// class MyFeature extends Feature with FileSystemFeature {
///   MyFeature() : super(
///     name: 'MyFeature',
///     config: FeatureConfig.production,
///   );
/// 
///   @override
///   Future<void> onInitialize() async {
///     // Setup
///   }
/// 
///   @override
///   Future<void> onDispose() async {
///     // Cleanup
///   }
/// }
/// ```
/// 
/// ## Architecture
/// 
/// ```
/// Feature (abstract base)
///   ├── Lifecycle Management (init, warmup, dispose)
///   ├── CircuitBreaker (fault tolerance)
///   ├── RetryPolicy (exponential backoff)
///   ├── HealthMonitoring (health checks, metrics)
///   ├── LogBuffer (diagnostic logging)
///   └── ResourceManagement (concurrency limits)
/// ```
library;

export 'feature.dart';
export 'feature_config.dart';
export 'feature_result.dart';
export 'circuit_breaker.dart';
export 'health_monitoring.dart';
export 'feature_registry.dart';

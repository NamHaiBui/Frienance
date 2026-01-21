# Feature Architecture

## Overview

The Frienance app uses a production-ready feature architecture that provides:

- **Lifecycle Management**: Proper initialization, warmup, and disposal
- **Resiliency**: Retry policies with exponential backoff
- **Circuit Breaker**: Fault tolerance and cascading failure prevention  
- **Health Monitoring**: Health checks and status reporting
- **Metrics Collection**: Performance and usage metrics
- **Log Buffering**: Diagnostic log capture and dump capability
- **Resource Management**: Concurrent operation limits

## Quick Start

### Creating a Feature

```dart
import 'package:frienance/src/core/feature/feature_exports.dart';

class MyFeature extends Feature with FileSystemFeature {
  MyFeature() : super(
    name: 'MyFeature',
    config: FeatureConfig.production,
  );

  @override
  Future<void> onInitialize() async {
    // Set up resources, connections, etc.
    setBaseDirectory('/path/to/cache');
  }

  @override
  Future<HealthCheckResult> performHealthCheck() async {
    // Verify feature is working correctly
    return HealthCheckResult(
      featureName: name,
      status: HealthStatus.healthy,
      message: 'Feature is operational',
    );
  }

  @override
  Future<void> onDispose() async {
    // Clean up resources
  }

  // Your feature methods
  Future<FeatureResult<String>> doWork(String input) {
    return execute(
      () async {
        // Your business logic here
        return 'result';
      },
      operationName: 'doWork',
    );
  }
}
```

### Using Features

```dart
// Initialize and use
final feature = MyFeature();
await feature.initialize();

final result = await feature.doWork('input');
result.fold(
  onSuccess: (value) => print('Success: $value'),
  onFailure: (error) => print('Error: ${error.message}'),
);

// Don't forget to dispose
await feature.dispose();
```

### Using the Feature Registry

```dart
import 'package:frienance/src/core/feature/feature_exports.dart';

// Register features at app startup
void main() async {
  final registry = FeatureRegistry.instance;
  
  registry.register(ReceiptExtractionFeature());
  registry.register(TextExtractionFeature());
  
  // Initialize all features
  final result = await registry.initialize();
  if (result.isFailure) {
    print('Some features failed to initialize');
  }
  
  // Run app...
  
  // Dispose all features at shutdown
  await registry.dispose();
}
```

## Configuration

### FeatureConfig

```dart
// Production defaults
final config = FeatureConfig.production;

// Custom configuration
final config = FeatureConfig(
  retry: RetryConfig(
    maxAttempts: 3,
    initialDelay: Duration(milliseconds: 500),
    maxDelay: Duration(seconds: 30),
    backoffMultiplier: 2.0,
  ),
  circuitBreaker: CircuitBreakerConfig(
    failureThreshold: 5,
    successThreshold: 2,
    timeout: Duration(seconds: 30),
  ),
  timeout: TimeoutConfig(
    operationTimeout: Duration(seconds: 30),
    initializationTimeout: Duration(seconds: 60),
  ),
  resource: ResourceConfig.mobile,
);
```

## Result Handling

Features return `FeatureResult<T>` which can be:

- `Success<T>`: Operation succeeded with value
- `Failure<T>`: Operation failed with error
- `PartialSuccess<T>`: Succeeded with warnings

```dart
final result = await feature.doWork('input');

// Pattern matching
switch (result) {
  case Success(value: final v):
    print('Got: $v');
  case Failure(error: final e):
    print('Failed: ${e.message}');
  case PartialSuccess(value: final v, warnings: final w):
    print('Got $v with ${w.length} warnings');
}

// Fold method
result.fold(
  onSuccess: (value) => handleSuccess(value),
  onFailure: (error) => handleError(error),
);

// Get value or default
final value = result.getOrElse('default');

// Chain operations
final transformed = result.map((v) => v.toUpperCase());
```

## Health Monitoring

```dart
// Check single feature
final health = await feature.checkHealth();
print(health.status); // healthy, degraded, unhealthy

// Check all features
final registry = FeatureRegistry.instance;
final aggregate = await registry.checkHealth();
print(aggregate.overallStatus);
```

## Metrics

```dart
// Get feature metrics
final metrics = feature.metricsSnapshot;
print('Success rate: ${metrics.successRate}%');
print('Avg duration: ${metrics.averageDurationMs}ms');
print('P95: ${metrics.p95DurationMs}ms');

// Get all metrics
final allMetrics = registry.getAllMetrics();
```

## Log Dumping

```dart
// Dump logs for debugging
final file = await feature.dumpLogs('/path/to/logs');

// Get recent logs programmatically
final logs = feature.getRecentLogs(count: 50);
for (final entry in logs) {
  print(entry.format());
}
```

## Circuit Breaker States

```
CLOSED → (failures exceed threshold) → OPEN
   ↑                                      ↓
   └── (successes in half-open) ←── HALF-OPEN ← (timeout expires)
```

- **Closed**: Normal operation, requests flow through
- **Open**: Requests immediately rejected (fail fast)
- **Half-Open**: Limited requests allowed to test recovery

## Best Practices

1. **Always use `execute()` for operations** - It provides retry, circuit breaker, and metrics
2. **Handle results properly** - Don't ignore failures
3. **Dispose features when done** - Prevents resource leaks
4. **Use appropriate log levels** - Debug for development, Warning+ for production
5. **Configure timeouts appropriately** - Based on expected operation duration
6. **Monitor health checks** - Set up periodic health monitoring

## Files

- `lib/src/core/feature/feature.dart` - Base Feature class
- `lib/src/core/feature/feature_config.dart` - Configuration classes
- `lib/src/core/feature/feature_result.dart` - Result types
- `lib/src/core/feature/circuit_breaker.dart` - Circuit breaker implementation
- `lib/src/core/feature/health_monitoring.dart` - Health checks and metrics
- `lib/src/core/feature/feature_registry.dart` - Feature registry
- `lib/services/receipt_parser/receipt_extraction_feature.dart` - Receipt extraction feature

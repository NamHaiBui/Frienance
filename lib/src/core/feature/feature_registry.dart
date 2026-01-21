/// Feature Registry - Centralized management of application features.
/// 
/// Provides a single point of access for:
/// - Feature lifecycle management
/// - Aggregate health checks
/// - Centralized metrics collection
/// - Log aggregation and dumping
library;
import 'dart:async';
import 'dart:io';

import 'package:frienance/src/core/feature/feature.dart';
import 'package:frienance/src/core/feature/feature_result.dart';
import 'package:frienance/utils/metrics.dart';


/// Singleton registry for managing all application features.
class FeatureRegistry {
  FeatureRegistry._();

  static final FeatureRegistry _instance = FeatureRegistry._();
  
  /// Get the singleton instance.
  static FeatureRegistry get instance => _instance;

  /// Registered features by name.
  final Map<String, Feature> _features = {};

  /// Initialization order (for ordered shutdown).
  final List<String> _initOrder = [];

  /// Whether the registry has been initialized.
  bool _initialized = false;

  /// Get all registered features.
  Map<String, Feature> get features => Map.unmodifiable(_features);

  /// Get all feature names.
  List<String> get featureNames => List.unmodifiable(_initOrder);

  /// Whether the registry has been initialized.
  bool get isInitialized => _initialized;

  /// Register a feature.
  /// 
  /// Features must be registered before [initialize] is called.
  void register<T extends Feature>(T feature) {
    if (_initialized) {
      throw StateError(
        'Cannot register features after initialization. '
        'Call register() before initialize().',
      );
    }

    if (_features.containsKey(feature.name)) {
      throw ArgumentError('Feature "${feature.name}" is already registered.');
    }

    _features[feature.name] = feature;
    _initOrder.add(feature.name);
  }

  /// Get a registered feature by name.
  T? getFeature<T extends Feature>(String name) {
    final feature = _features[name];
    if (feature is T) return feature;
    return null;
  }

  /// Get a required feature by name (throws if not found).
  T requireFeature<T extends Feature>(String name) {
    final feature = getFeature<T>(name);
    if (feature == null) {
      throw StateError(
        'Feature "$name" not found or is not of type $T. '
        'Available features: ${_features.keys.join(', ')}',
      );
    }
    return feature;
  }

  /// Initialize all registered features.
  /// 
  /// Features are initialized in registration order.
  /// If a feature fails to initialize, subsequent features are still attempted.
  Future<FeatureResult<RegistryInitResult>> initialize() async {
    if (_initialized) {
      return Success(RegistryInitResult(
        successful: const [],
        failed: const {},
        alreadyInitialized: true,
      ));
    }

    final successful = <String>[];
    final failed = <String, FeatureError>{};

    for (final name in _initOrder) {
      final feature = _features[name]!;
      final result = await feature.initialize();

      result.fold(
        onSuccess: (_) => successful.add(name),
        onFailure: (error) => failed[name] = error,
      );
    }

    _initialized = true;

    if (failed.isEmpty) {
      return Success(RegistryInitResult(
        successful: successful,
        failed: failed,
      ));
    } else {
      return PartialSuccess(
        RegistryInitResult(successful: successful, failed: failed),
        failed.entries
            .map((e) => FeatureWarning(
                  code: 'FEATURE_INIT_FAILED',
                  message: 'Feature "${e.key}" failed to initialize: ${e.value.message}',
                ))
            .toList(),
      );
    }
  }

  /// Warm up all features that are ready.
  Future<void> warmUp() async {
    for (final feature in _features.values) {
      if (feature.isReady) {
        await feature.warmUp();
      }
    }
  }
  /// Get aggregated metrics from all features.
  Map<String, MetricsSnapshot> getAllMetrics() {
    return Map.fromEntries(
      _features.entries.map((e) => MapEntry(e.key, e.value.metricsSnapshot)),
    );
  }

  /// Dump logs from all features to a directory.
  Future<List<File>> dumpAllLogs(String directory) async {
    final files = <File>[];
    
    for (final feature in _features.values) {
      try {
        final file = await feature.dumpLogs(directory);
        files.add(file);
      } catch (e) {
        // Continue dumping other features
      }
    }

    return files;
  }

  /// Dispose all features.
  /// 
  /// Features are disposed in reverse initialization order.
  Future<void> dispose() async {
    for (final name in _initOrder.reversed) {
      final feature = _features[name];
      if (feature != null && !feature.isDisposed) {
        await feature.dispose();
      }
    }

    _features.clear();
    _initOrder.clear();
    _initialized = false;
  }

  /// Unregister a specific feature.
  Future<void> unregister(String name) async {
    final feature = _features.remove(name);
    if (feature != null) {
      _initOrder.remove(name);
      if (!feature.isDisposed) {
        await feature.dispose();
      }
    }
  }

  /// Reset the registry (for testing).
  Future<void> reset() async {
    await dispose();
  }
}

/// Result of registry initialization.
class RegistryInitResult {
  const RegistryInitResult({
    required this.successful,
    required this.failed,
    this.alreadyInitialized = false,
  });

  /// Names of features that initialized successfully.
  final List<String> successful;

  /// Map of feature names to their initialization errors.
  final Map<String, FeatureError> failed;

  /// Whether the registry was already initialized.
  final bool alreadyInitialized;

  /// Total number of features.
  int get totalFeatures => successful.length + failed.length;

  /// Whether all features initialized successfully.
  bool get allSuccessful => failed.isEmpty;

  Map<String, dynamic> toJson() => {
    'successful': successful,
    'failed': failed.map((k, v) => MapEntry(k, v.toString())),
    'alreadyInitialized': alreadyInitialized,
    'successRate': totalFeatures > 0 
        ? '${(successful.length / totalFeatures * 100).toStringAsFixed(1)}%'
        : '100%',
  };

  @override
  String toString() => 'RegistryInitResult('
      'successful: ${successful.length}, '
      'failed: ${failed.length}, '
      'alreadyInitialized: $alreadyInitialized)';
}

/// Extension for convenient feature access.
extension FeatureRegistryExtension on FeatureRegistry {
  /// Initialize and get a feature.
  Future<T> initializeAndGet<T extends Feature>(String name) async {
    if (!_initialized) {
      await initialize();
    }
    return requireFeature<T>(name);
  }
}

/// Mixin for classes that need access to the feature registry.
mixin FeatureRegistryAccess {
  /// Get the feature registry.
  FeatureRegistry get featureRegistry => FeatureRegistry.instance;

  /// Get a feature by name.
  T? getFeature<T extends Feature>(String name) =>
      featureRegistry.getFeature<T>(name);

  /// Get a required feature by name.
  T requireFeature<T extends Feature>(String name) =>
      featureRegistry.requireFeature<T>(name);
}

/// Riverpod providers for AdaptiveFuzzyMatcher state management.
///
/// Provides a production-ready state management layer for the adaptive
/// fuzzy matching feature, integrating with the Feature infrastructure.
library;

import 'dart:io';

import 'package:frienance/utils/metrics.dart';
import 'package:frienance/utils/logger.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:riverpod/riverpod.dart';

import 'package:frienance/services/receipt_parser/adaptive_fuzzy_matcher.dart';
import 'package:frienance/services/receipt_parser/utils/fuzzy_matching_utils/model/extraction_results.dart';
import 'package:frienance/src/core/feature/feature.dart';
import 'package:frienance/src/core/feature/feature_config.dart';
import 'package:frienance/src/core/feature/feature_result.dart';
import 'package:frienance/src/core/feature/circuit_breaker.dart';
import 'package:frienance/src/core/feature/health_monitoring.dart';

// ============================================================
// CONFIG PATH PROVIDER
// ============================================================

/// Provides the config file path for the adaptive fuzzy matcher.
final configPathProvider = FutureProvider<String>((ref) async {
  final appDocDir = await getApplicationDocumentsDirectory();
  final configDir = Directory(p.join(appDocDir.path, 'frienance'));

  // Ensure directory exists
  if (!await configDir.exists()) {
    await configDir.create(recursive: true);
  }

  return p.join(configDir.path, 'fuzzy_matcher_config.json');
});

// ============================================================
// ADAPTIVE FUZZY MATCHER PROVIDER
// ============================================================

/// State notifier for AdaptiveFuzzyMatcher lifecycle and operations.
class AdaptiveFuzzyMatcherNotifier
    extends Notifier<AsyncValue<AdaptiveFuzzyMatcher>> {
  @override
  AsyncValue<AdaptiveFuzzyMatcher> build() {
    // Start in loading state
    _initialize();
    return const AsyncValue.loading();
  }

  Future<void> _initialize() async {
    try {
      final configPath = await ref.watch(configPathProvider.future);

      final matcher = AdaptiveFuzzyMatcher(
        configPath,
        config: const FeatureConfig(
          retry: RetryConfig(maxAttempts: 3),
          timeout: TimeoutConfig(
            operationTimeout: Duration(seconds: 10),
            initializationTimeout: Duration(seconds: 30),
          ),
          logLevel: LogLevel.info,
        ),
      );

      // Initialize the feature
      final initResult = await matcher.initialize();

      if (initResult.isFailure) {
        state = AsyncValue.error(
          initResult.errorOrNull?.message ?? 'Failed to initialize matcher',
          StackTrace.current,
        );
        return;
      }

      // Set up callback to notify when config changes (learning occurs)
      matcher.onLearned = () {
        // Trigger a rebuild to reflect changes
        ref.invalidateSelf();
      };

      state = AsyncValue.data(matcher);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  /// Reinitialize the matcher (useful after errors or config changes).
  Future<void> reinitialize() async {
    state = const AsyncValue.loading();
    await _initialize();
  }

  /// Reload the matcher's config without full reinitialization.
  void reload() {
    state.whenData((matcher) {
      matcher.reload();
    });
  }

  /// Dispose the matcher when no longer needed.
  Future<void> disposeMatcher() async {
    final matcher = state.value;
    if (matcher != null) {
      await matcher.dispose();
    }
  }
}

/// Main provider for AdaptiveFuzzyMatcher with Riverpod state management.
final adaptiveFuzzyMatcherProvider = NotifierProvider<
    AdaptiveFuzzyMatcherNotifier, AsyncValue<AdaptiveFuzzyMatcher>>(
  AdaptiveFuzzyMatcherNotifier.new,
);

// ============================================================
// DERIVED STATE PROVIDERS
// ============================================================

/// Provides the current feature state of the matcher.
final matcherStateProvider = Provider<FeatureState?>((ref) {
  return ref.watch(adaptiveFuzzyMatcherProvider).whenOrNull(
        data: (matcher) => matcher.state,
      );
});

/// Provides whether the matcher is ready for use.
final matcherIsReadyProvider = Provider<bool>((ref) {
  return ref.watch(adaptiveFuzzyMatcherProvider).whenOrNull(
            data: (matcher) => matcher.isReady,
          ) ??
      false;
});

/// Provides the circuit breaker stats for monitoring.
final matcherCircuitBreakerStatsProvider =
    Provider<CircuitBreakerStats?>((ref) {
  return ref.watch(adaptiveFuzzyMatcherProvider).whenOrNull(
        data: (matcher) => matcher.circuitBreakerStats,
      );
});

/// Provides the metrics snapshot for monitoring.
final matcherMetricsProvider = Provider<MetricsSnapshot?>((ref) {
  return ref.watch(adaptiveFuzzyMatcherProvider).whenOrNull(
        data: (matcher) => matcher.metricsSnapshot,
      );
});

// ============================================================
// EXTRACTION PROVIDERS
// ============================================================

/// State class for extraction input.
class ExtractionInput {
  final List<String> lines;

  const ExtractionInput(this.lines);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExtractionInput &&
          runtimeType == other.runtimeType &&
          _listEquals(lines, other.lines);

  @override
  int get hashCode => Object.hashAll(lines);

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Family provider for extraction results based on input lines.
final extractionResultProvider =
    FutureProvider.family<ExtractionResult?, ExtractionInput>(
  (ref, input) async {
    final matcherAsync = ref.watch(adaptiveFuzzyMatcherProvider);

    return matcherAsync.whenOrNull(
      data: (matcher) => matcher.extractAll(input.lines),
    );
  },
);

/// Provider for performing extraction with resilience (uses Feature.execute).
final resilientExtractionProvider =
    FutureProvider.family<FeatureResult<ExtractionResult>, ExtractionInput>(
  (ref, input) async {
    final matcherAsync = ref.watch(adaptiveFuzzyMatcherProvider);

    final matcher = matcherAsync.value;
    if (matcher == null) {
      return Failure(FeatureError(
        code: FeatureError.codeNotInitialized,
        message: 'Matcher is not initialized',
      ));
    }

    return matcher.execute(
      () async => matcher.extractAll(input.lines),
      operationName: 'extractAll',
    );
  },
);

// ============================================================
// STORE MANAGEMENT PROVIDERS
// ============================================================

/// Provides all stores/restaurants in the config.
final storesProvider = Provider<Map<String, List<String>>>((ref) {
  return ref.watch(adaptiveFuzzyMatcherProvider).whenOrNull(
            data: (matcher) => matcher.getStores(),
          ) ??
      {};
});

/// Provides all categories.
final categoriesProvider = Provider<List<String>>((ref) {
  return ref.watch(adaptiveFuzzyMatcherProvider).whenOrNull(
            data: (matcher) => matcher.getCategories(),
          ) ??
      [];
});

/// Family provider for stores in a specific category.
final storesInCategoryProvider =
    Provider.family<List<String>, String>((ref, category) {
  return ref.watch(adaptiveFuzzyMatcherProvider).whenOrNull(
            data: (matcher) => matcher.getStoresInCategory(category),
          ) ??
      [];
});

/// Family provider for spellings of a specific store.
final storeSpellingsProvider =
    Provider.family<List<String>?, String>((ref, storeName) {
  return ref.watch(adaptiveFuzzyMatcherProvider).whenOrNull(
        data: (matcher) => matcher.getSpellings(storeName),
      );
});

// ============================================================
// STATS PROVIDERS
// ============================================================

/// Provides extraction statistics.
final extractionStatsProvider = Provider<Map<String, dynamic>>((ref) {
  return ref.watch(adaptiveFuzzyMatcherProvider).whenOrNull(
            data: (matcher) => matcher.getStats(),
          ) ??
      {};
});

// ============================================================
// HEALTH CHECK PROVIDERS
// ============================================================

/// Provides health check result for the matcher.
final matcherHealthCheckProvider =
    FutureProvider<HealthCheckResult?>((ref) async {
  final matcherAsync = ref.watch(adaptiveFuzzyMatcherProvider);

  final matcher = matcherAsync.value;
  if (matcher == null) {
    return null;
  }

  return matcher.checkHealth();
});

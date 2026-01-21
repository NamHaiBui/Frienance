/// Result types for feature operations.
/// 
/// Provides a robust way to handle success, failure, and partial results
/// without relying on exceptions for control flow.
library;

import 'dart:async';

/// Represents the result of a feature operation.
/// 
/// Inspired by functional programming's Either/Result pattern,
/// this provides a type-safe way to handle success and failure cases.
sealed class FeatureResult<T> {
  const FeatureResult();

  /// Whether this result represents a successful operation.
  bool get isSuccess;

  /// Whether this result represents a failed operation.
  bool get isFailure => !isSuccess;

  /// Get the value if successful, or null if failed.
  T? get valueOrNull;

  /// Get the error if failed, or null if successful.
  FeatureError? get errorOrNull;

  /// Map the success value to a new type.
  FeatureResult<R> map<R>(R Function(T value) transform);

  /// FlatMap the success value to a new result.
  FeatureResult<R> flatMap<R>(FeatureResult<R> Function(T value) transform);

  /// Execute a callback based on success or failure.
  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(FeatureError error) onFailure,
  });

  /// Get the value or throw the error.
  T getOrThrow();

  /// Get the value or return a default.
  T getOrElse(T defaultValue);

  /// Get the value or compute a default.
  T getOrCompute(T Function() compute);

  /// Convert to a Future that completes with the value or errors.
  Future<T> toFuture();
}

/// Successful result containing a value.
final class Success<T> extends FeatureResult<T> {
  const Success(this.value);

  final T value;

  @override
  bool get isSuccess => true;

  @override
  T? get valueOrNull => value;

  @override
  FeatureError? get errorOrNull => null;

  @override
  FeatureResult<R> map<R>(R Function(T value) transform) {
    return Success(transform(value));
  }

  @override
  FeatureResult<R> flatMap<R>(FeatureResult<R> Function(T value) transform) {
    return transform(value);
  }

  @override
  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(FeatureError error) onFailure,
  }) {
    return onSuccess(value);
  }

  @override
  T getOrThrow() => value;

  @override
  T getOrElse(T defaultValue) => value;

  @override
  T getOrCompute(T Function() compute) => value;

  @override
  Future<T> toFuture() => Future.value(value);

  @override
  String toString() => 'Success($value)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Success<T> && runtimeType == other.runtimeType && value == other.value;

  @override
  int get hashCode => value.hashCode;
}

/// Failed result containing an error.
final class Failure<T> extends FeatureResult<T> {
  const Failure(this.error);

  final FeatureError error;

  @override
  bool get isSuccess => false;

  @override
  T? get valueOrNull => null;

  @override
  FeatureError? get errorOrNull => error;

  @override
  FeatureResult<R> map<R>(R Function(T value) transform) {
    return Failure(error);
  }

  @override
  FeatureResult<R> flatMap<R>(FeatureResult<R> Function(T value) transform) {
    return Failure(error);
  }

  @override
  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(FeatureError error) onFailure,
  }) {
    return onFailure(error);
  }

  @override
  T getOrThrow() => throw error.toException();

  @override
  T getOrElse(T defaultValue) => defaultValue;

  @override
  T getOrCompute(T Function() compute) => compute();

  @override
  Future<T> toFuture() => Future.error(error.toException());

  @override
  String toString() => 'Failure($error)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Failure<T> && runtimeType == other.runtimeType && error == other.error;

  @override
  int get hashCode => error.hashCode;
}

/// Partial success with value and non-fatal issues.
final class PartialSuccess<T> extends FeatureResult<T> {
  const PartialSuccess(this.value, this.warnings);

  final T value;
  final List<FeatureWarning> warnings;

  @override
  bool get isSuccess => true;

  @override
  T? get valueOrNull => value;

  @override
  FeatureError? get errorOrNull => null;

  @override
  FeatureResult<R> map<R>(R Function(T value) transform) {
    return PartialSuccess(transform(value), warnings);
  }

  @override
  FeatureResult<R> flatMap<R>(FeatureResult<R> Function(T value) transform) {
    final result = transform(value);
    if (result is PartialSuccess<R>) {
      return PartialSuccess(result.value, [...warnings, ...result.warnings]);
    }
    return result;
  }

  @override
  R fold<R>({
    required R Function(T value) onSuccess,
    required R Function(FeatureError error) onFailure,
  }) {
    return onSuccess(value);
  }

  @override
  T getOrThrow() => value;

  @override
  T getOrElse(T defaultValue) => value;

  @override
  T getOrCompute(T Function() compute) => value;

  @override
  Future<T> toFuture() => Future.value(value);

  @override
  String toString() => 'PartialSuccess($value, warnings: ${warnings.length})';
}

/// Error information for failed operations.
class FeatureError {
  const FeatureError({
    required this.code,
    required this.message,
    this.cause,
    this.stackTrace,
    this.context = const {},
    this.recoverable = false,
  });

  /// Error code for programmatic handling.
  final String code;

  /// Human-readable error message.
  final String message;

  /// Original exception that caused this error.
  final Object? cause;

  /// Stack trace of the original error.
  final StackTrace? stackTrace;

  /// Additional context about the error.
  final Map<String, dynamic> context;

  /// Whether this error might be recoverable with retry.
  final bool recoverable;

  /// Create a FeatureError from an exception.
  factory FeatureError.fromException(
    Object exception, {
    StackTrace? stackTrace,
    String? code,
    Map<String, dynamic> context = const {},
  }) {
    return FeatureError(
      code: code ?? _inferErrorCode(exception),
      message: exception.toString(),
      cause: exception,
      stackTrace: stackTrace,
      context: context,
      recoverable: _isRecoverable(exception),
    );
  }

  /// Convert this error back to an exception.
  FeatureException toException() {
    return FeatureException(this);
  }

  static String _inferErrorCode(Object exception) {
    return switch (exception) {
      FormatException() => 'FORMAT_ERROR',
      TimeoutException() => 'TIMEOUT',
      ArgumentError() => 'INVALID_ARGUMENT',
      StateError() => 'INVALID_STATE',
      UnsupportedError() => 'UNSUPPORTED',
      _ when exception.runtimeType.toString().contains('IO') => 'IO_ERROR',
      _ when exception.runtimeType.toString().contains('Socket') => 'NETWORK_ERROR',
      _ => 'UNKNOWN_ERROR',
    };
  }

  static bool _isRecoverable(Object exception) {
    return switch (exception) {
      TimeoutException() => true,
      _ when exception.runtimeType.toString().contains('Socket') => true,
      _ when exception.runtimeType.toString().contains('IO') => true,
      _ => false,
    };
  }

  @override
  String toString() => 'FeatureError[$code]: $message';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FeatureError &&
          runtimeType == other.runtimeType &&
          code == other.code &&
          message == other.message;

  @override
  int get hashCode => Object.hash(code, message);

  /// Common error codes.
  static const String codeCircuitOpen = 'CIRCUIT_OPEN';
  static const String codeTimeout = 'TIMEOUT';
  static const String codeRetryExhausted = 'RETRY_EXHAUSTED';
  static const String codeCancelled = 'CANCELLED';
  static const String codeNotInitialized = 'NOT_INITIALIZED';
  static const String codeResourceExhausted = 'RESOURCE_EXHAUSTED';
  static const String codeValidation = 'VALIDATION_ERROR';
  static const String codeInternal = 'INTERNAL_ERROR';
}

/// Non-fatal warning for partial successes.
class FeatureWarning {
  const FeatureWarning({
    required this.code,
    required this.message,
    this.context = const {},
  });

  final String code;
  final String message;
  final Map<String, dynamic> context;

  @override
  String toString() => 'Warning[$code]: $message';
}

/// Exception wrapper for FeatureError.
class FeatureException implements Exception {
  const FeatureException(this.error);

  final FeatureError error;

  @override
  String toString() => error.toString();
}

/// Extension to convert futures to results.
extension FutureToResult<T> on Future<T> {
  /// Convert a Future to a FeatureResult, catching any errors.
  Future<FeatureResult<T>> toResult() async {
    try {
      final value = await this;
      return Success(value);
    } catch (e, st) {
      return Failure(FeatureError.fromException(e, stackTrace: st));
    }
  }
}

/// Extension to chain result operations.
extension ResultChaining<T> on Future<FeatureResult<T>> {
  /// Map the success value asynchronously.
  Future<FeatureResult<R>> mapAsync<R>(Future<R> Function(T value) transform) async {
    final result = await this;
    return result.fold(
      onSuccess: (value) async => Success(await transform(value)),
      onFailure: (error) => Failure(error),
    );
  }

  /// FlatMap the success value asynchronously.
  Future<FeatureResult<R>> flatMapAsync<R>(
    Future<FeatureResult<R>> Function(T value) transform,
  ) async {
    final result = await this;
    return result.fold(
      onSuccess: (value) => transform(value),
      onFailure: (error) => Failure(error),
    );
  }
}

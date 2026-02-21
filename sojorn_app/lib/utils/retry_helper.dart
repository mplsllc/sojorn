// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'dart:async';

/// Helper for retrying failed operations with exponential backoff
class RetryHelper {
  /// Retry an operation with exponential backoff
  static Future<T> retry<T>({
    required Future<T> Function() operation,
    int maxAttempts = 3,
    Duration initialDelay = const Duration(seconds: 1),
    double backoffMultiplier = 2.0,
    bool Function(dynamic error)? retryIf,
  }) async {
    int attempt = 0;
    Duration delay = initialDelay;

    while (true) {
      try {
        return await operation();
      } catch (e) {
        attempt++;

        // Check if we should retry this error
        if (retryIf != null && !retryIf(e)) {
          rethrow;
        }

        if (attempt >= maxAttempts) {
          rethrow; // Give up after max attempts
        }

        // Wait before retrying with exponential backoff
        await Future.delayed(delay);
        delay = Duration(
          milliseconds: (delay.inMilliseconds * backoffMultiplier).round(),
        );
      }
    }
  }

  /// Retry specifically for network operations
  static Future<T> retryNetwork<T>({
    required Future<T> Function() operation,
    int maxAttempts = 3,
  }) async {
    return retry(
      operation: operation,
      maxAttempts: maxAttempts,
      retryIf: (error) {
        // Retry on network errors, timeouts, and 5xx server errors
        final errorStr = error.toString().toLowerCase();
        return errorStr.contains('socket') ||
            errorStr.contains('timeout') ||
            errorStr.contains('500') ||
            errorStr.contains('502') ||
            errorStr.contains('503') ||
            errorStr.contains('504');
      },
    );
  }
}

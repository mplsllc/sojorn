import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'snackbar_ext.dart';

/// Global error handler for consistent error messaging and logging
class ErrorHandler {
  /// Handle an error and optionally show a snackbar to the user
  static void handleError(
    dynamic error, {
    required BuildContext context,
    String? userMessage,
    bool showSnackbar = true,
  }) {
    final displayMessage = _getDisplayMessage(error, userMessage);
    
    // Log to console (in production, send to analytics/crash reporting)
    _logError(error, displayMessage);
    
    if (showSnackbar && context.mounted) {
      context.showError(displayMessage);
    }
  }

  /// Get user-friendly error message
  static String _getDisplayMessage(dynamic error, String? userMessage) {
    if (userMessage != null) return userMessage;

    if (error is SocketException) {
      return 'No internet connection. Please check your network.';
    } else if (error is TimeoutException) {
      return 'Request timed out. Please try again.';
    } else if (error is FormatException) {
      return 'Invalid data format received.';
    } else if (error.toString().contains('401')) {
      return 'Authentication error. Please sign in again.';
    } else if (error.toString().contains('403')) {
      return 'You don\'t have permission to do that.';
    } else if (error.toString().contains('404')) {
      return 'Resource not found.';
    } else if (error.toString().contains('500')) {
      return 'Server error. Please try again later.';
    } else {
      return 'Something went wrong. Please try again.';
    }
  }

  /// Log error for debugging/analytics
  static void _logError(dynamic error, String message) {
    // In production, send to Sentry, Firebase Crashlytics, etc.
    debugPrint('ERROR: $message');
    debugPrint('Details: ${error.toString()}');
    if (error is Error) {
      debugPrint('Stack trace: ${error.stackTrace}');
    }
  }
}

/// Wrapper for async operations with automatic error handling
Future<T?> safeExecute<T>({
  required Future<T> Function() operation,
  required BuildContext context,
  String? errorMessage,
  bool showError = true,
}) async {
  try {
    return await operation();
  } catch (e) {
    if (showError) {
      ErrorHandler.handleError(
        e,
        context: context,
        userMessage: errorMessage,
      );
    }
    return null;
  }
}

// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

/// Security utilities for input validation and sanitization
class SecurityUtils {
  /// Sanitize user-generated text content
  static String sanitizeText(String input) {
    if (input.isEmpty) return input;
    
    // Remove potentially dangerous characters
    String sanitized = input
        .replaceAll(RegExp(r'<script[^>]*>.*?</script>'), '') // Remove script tags
        .replaceAll(RegExp(r'<iframe[^>]*>.*?</iframe>'), '') // Remove iframe tags
        .replaceAll(RegExp(r'<object[^>]*>.*?</object>'), '') // Remove object tags
        .replaceAll(RegExp(r'<embed[^>]*>.*?</embed>'), '') // Remove embed tags
        .replaceAll(RegExp(r'<link[^>]*>.*?</link>'), '') // Remove link tags
        .replaceAll(RegExp(r'<meta[^>]*>.*?</meta>'), '') // Remove meta tags
        .replaceAll(RegExp(r'javascript:'), '') // Remove javascript: protocol
        .replaceAll(RegExp(r'vbscript:'), '') // Remove vbscript: protocol
        .replaceAll(RegExp(r'on\w+\s*='), '') // Remove event handlers
        .replaceAll(RegExp(r'eval\s*\('), '') // Remove eval calls
        .replaceAll(RegExp(r'expression\s*\('), '') // Remove expression calls
        .trim();
    
    return sanitized;
  }

  /// Validate and sanitize URLs
  static String? sanitizeUrl(String url) {
    if (url.isEmpty) return null;
    
    try {
      final uri = Uri.parse(url.startsWith('http') ? url : 'https://$url');
      
      // Only allow safe protocols
      if (!['http', 'https'].contains(uri.scheme)) {
        return null;
      }
      
      // Remove potentially dangerous query parameters
      final sanitizedParams = <String, String>{};
      uri.queryParameters.forEach((key, value) {
        // Remove dangerous query parameters
        if (!_isDangerousQueryParam(key) && !_isDangerousQueryParam(value)) {
          sanitizedParams[key] = value;
        }
      });
      
      final sanitizedUri = Uri(
        scheme: uri.scheme,
        host: uri.host,
        port: uri.port,
        path: uri.path,
        queryParameters: sanitizedParams,
      );
      
      return sanitizedUri.toString();
    } catch (e) {
      return null;
    }
  }

  /// Check if a query parameter is dangerous
  static bool _isDangerousQueryParam(String value) {
    final dangerousPatterns = [
      'script', 'javascript', 'vbscript', 'onload', 'onerror', 'onclick',
      'eval', 'expression', 'alert', 'confirm', 'prompt',
      '<', '>', '"', "'", '\\', '\n', '\r', '\t'
    ];

    
    final lowerValue = value.toLowerCase();
    return dangerousPatterns.any((pattern) => lowerValue.contains(pattern));
  }

  /// Validate and limit text length
  static String limitText(String text, {int maxLength = 1000}) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength)}...';
  }

  /// Check for potential XSS patterns
  static bool containsXSS(String input) {
    final xssPatterns = [
      RegExp(r'<script[^>]*>', caseSensitive: false),
      RegExp(r'javascript:', caseSensitive: false),
      RegExp(r'vbscript:', caseSensitive: false),
      RegExp(r'on\w+\s*=', caseSensitive: false),
      RegExp(r'eval\s*\(', caseSensitive: false),
      RegExp(r'expression\s*\(', caseSensitive: false),
      RegExp(r'<iframe', caseSensitive: false),
      RegExp(r'<object', caseSensitive: false),
      RegExp(r'<embed', caseSensitive: false),
    ];
    
    return xssPatterns.any((pattern) => pattern.hasMatch(input));
  }

  /// Validate user input for common attacks
  static bool isValidInput(String input) {
    if (input.isEmpty) return true;
    
    // Check for SQL injection patterns
    final sqlPatterns = [
      RegExp(r'(\b(SELECT|INSERT|UPDATE|DELETE|DROP|CREATE|ALTER|EXEC|UNION|SCRIPT)\b)', caseSensitive: false),
      RegExp(r'(--|#|/\*|\*/)', caseSensitive: false),
      RegExp(r'\bOR\b.*?=.*=', caseSensitive: false),
      RegExp(r'\bAND\b.*?=.*=', caseSensitive: false),
    ];
    
    return !sqlPatterns.any((pattern) => pattern.hasMatch(input));
  }

  /// Sanitize HTML content (if needed)
  static String sanitizeHtml(String html) {
    // Basic HTML sanitization - remove all tags
    return html.replaceAll(RegExp(r'<[^>]*>'), '').trim();
  }

  /// Validate email format
  static bool isValidEmail(String email) {
    final emailRegex = RegExp(
      r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$',
    );
    return emailRegex.hasMatch(email);
  }

  /// Validate handle/username
  static bool isValidHandle(String handle) {
    if (handle.isEmpty) return false;
    if (handle.length < 3 || handle.length > 30) return false;
    
    final handleRegex = RegExp(r'^[a-zA-Z0-9_]+$');
    return handleRegex.hasMatch(handle);
  }

  /// Remove potentially harmful characters from filenames
  static String sanitizeFilename(String filename) {
    return filename
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '')
        .replaceAll(RegExp(r'\.\.'), '.')
        .replaceAll(RegExp(r'^\.+|\.+$'), '')
        .toLowerCase();
  }
}

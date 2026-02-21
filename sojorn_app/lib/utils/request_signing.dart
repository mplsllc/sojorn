// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';

/// Request signing utility for critical API operations
class RequestSigning {
  /// Generate HMAC-SHA256 signature for request
  static String signRequest(
    String method,
    String path,
    Map<String, dynamic>? body,
    String timestamp,
    String secretKey,
  ) {
    // Create canonical request
    final canonicalRequest = _buildCanonicalRequest(method, path, body, timestamp);
    
    // Generate HMAC-SHA256 signature
    final key = utf8.encode(secretKey);
    final hmac = Hmac(sha256, key);
    final digest = hmac.convert(utf8.encode(canonicalRequest));
    
    return digest.toString();
  }
  
  /// Build canonical request string for signing
  static String _buildCanonicalRequest(
    String method,
    String path,
    Map<String, dynamic>? body,
    String timestamp,
  ) {
    final parts = [
      method.toUpperCase(),
      path,
      timestamp,
    ];
    
    if (body != null && body.isNotEmpty) {
      final sortedBody = Map<String, dynamic>.fromEntries(
        body.entries.toList()..sort((a, b) => a.key.compareTo(b.key))
      );
      parts.add(jsonEncode(sortedBody));
    }
    
    return parts.join('\n');
  }
  
  /// Verify request signature
  static bool verifySignature(
    String method,
    String path,
    Map<String, dynamic>? body,
    String timestamp,
    String signature,
    String secretKey,
  ) {
    final expectedSignature = signRequest(method, path, body, timestamp, secretKey);
    return _constantTimeEquals(signature, expectedSignature);
  }
  
  /// Constant-time comparison to prevent timing attacks
  static bool _constantTimeEquals(String a, String b) {
    if (a.length != b.length) return false;
    
    int result = 0;
    for (int i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    
    return result == 0;
  }
  
  /// Generate timestamp for request signing
  static String generateTimestamp() {
    return DateTime.now().toUtc().toIso8601String().replaceAll('.', '').replaceAll('Z', '');
  }
  
  /// Add signature headers to request
  static Map<String, String> addSignatureHeaders(
    Map<String, String> headers,
    String method,
    String path,
    Map<String, dynamic>? body,
    String secretKey,
  ) {
    final timestamp = generateTimestamp();
    final signature = signRequest(method, path, body, timestamp, secretKey);
    
    final signedHeaders = Map<String, String>.from(headers);
    signedHeaders['X-Timestamp'] = timestamp;
    signedHeaders['X-Signature'] = signature;
    signedHeaders['X-Algorithm'] = 'HMAC-SHA256';
    
    return signedHeaders;
  }
}

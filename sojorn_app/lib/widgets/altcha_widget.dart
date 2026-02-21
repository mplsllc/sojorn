// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'dart:convert';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';
import '../theme/app_theme.dart';

class AltchaWidget extends StatefulWidget {
  final String? apiUrl;
  final Function(String) onVerified;
  final Function(String)? onError;

  const AltchaWidget({
    super.key,
    this.apiUrl,
    required this.onVerified,
    this.onError,
  });

  @override
  State<AltchaWidget> createState() => _AltchaWidgetState();
}

class _AltchaWidgetState extends State<AltchaWidget> {
  bool _isLoading = true;
  bool _isSolving = false;
  bool _isVerified = false;
  String? _errorMessage;
  Map<String, dynamic>? _challengeData;

  @override
  void initState() {
    super.initState();
    _loadChallenge();
  }

  Future<void> _loadChallenge() async {
    setState(() {
      _isLoading = true;
      _isVerified = false;
      _isSolving = false;
      _errorMessage = null;
    });

    try {
      final url = widget.apiUrl ?? '${ApiConfig.baseUrl}/auth/altcha-challenge';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _challengeData = data;
          _isLoading = false;
        });
        // Auto-solve in the background
        _solveChallenge(data);
      } else {
        _setError('Failed to load challenge (${response.statusCode})');
      }
    } catch (e) {
      _setError('Network error: unable to reach server');
    }
  }

  void _setError(String msg) {
    if (mounted) {
      setState(() {
        _isLoading = false;
        _isSolving = false;
        _errorMessage = msg;
      });
      widget.onError?.call(msg);
    }
  }

  Future<void> _solveChallenge(Map<String, dynamic> data) async {
    setState(() => _isSolving = true);

    try {
      final algorithm = data['algorithm'] as String? ?? 'SHA-256';
      final challenge = data['challenge'] as String;
      final salt = data['salt'] as String;
      final signature = data['signature'] as String;
      final maxNumber = (data['maxnumber'] as num?)?.toInt() ?? 100000;

      // Solve proof-of-work in an isolate to avoid blocking UI
      final number = await compute(_solvePow, _PowParams(
        algorithm: algorithm,
        challenge: challenge,
        salt: salt,
        maxNumber: maxNumber,
      ));

      if (number == null) {
        _setError('Could not solve challenge');
        return;
      }

      // Build the payload the server expects (base64-encoded JSON)
      final payload = {
        'algorithm': algorithm,
        'challenge': challenge,
        'number': number,
        'salt': salt,
        'signature': signature,
      };

      final token = base64Encode(utf8.encode(json.encode(payload)));

      if (mounted) {
        setState(() {
          _isSolving = false;
          _isVerified = true;
        });
        widget.onVerified(token);
      }
    } catch (e) {
      _setError('Verification error');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return _buildContainer(
        borderColor: Colors.red.withValues(alpha: 0.5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 20),
            const SizedBox(width: 8),
            Flexible(
              child: Text(_errorMessage!,
                  style: const TextStyle(color: Colors.red, fontSize: 13)),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: _loadChallenge,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_isLoading || _isSolving) {
      return _buildContainer(
        borderColor: AppTheme.egyptianBlue.withValues(alpha: 0.3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 10),
            Text(
              _isLoading ? 'Loading verification...' : 'Verifying...',
              style: TextStyle(
                color: Colors.grey[400],
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    if (_isVerified) {
      return _buildContainer(
        borderColor: AppTheme.success.withValues(alpha: 0.5),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: AppTheme.success, size: 20),
            const SizedBox(width: 8),
            Text('Verified',
                style: TextStyle(color: AppTheme.success, fontSize: 13)),
          ],
        ),
      );
    }

    // Fallback (shouldn't normally reach here since we auto-solve)
    return _buildContainer(
      borderColor: AppTheme.egyptianBlue.withValues(alpha: 0.3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.security, color: Colors.blue, size: 20),
          const SizedBox(width: 8),
          const Text('Waiting for verification...',
              style: TextStyle(color: Colors.grey, fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildContainer({required Color borderColor, required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: 1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: child,
    );
  }
}

// Proof-of-work parameters for isolate
class _PowParams {
  final String algorithm;
  final String challenge;
  final String salt;
  final int maxNumber;

  _PowParams({
    required this.algorithm,
    required this.challenge,
    required this.salt,
    required this.maxNumber,
  });
}

// Runs in a separate isolate so the UI stays responsive
int? _solvePow(_PowParams params) {
  for (int n = 0; n <= params.maxNumber; n++) {
    final input = '${params.salt}$n';
    final hash = sha256.convert(utf8.encode(input)).toString();
    if (hash == params.challenge) {
      return n;
    }
  }
  return null;
}

// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'dart:convert';
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
  bool _isLoading = false;
  bool _isSolving = false;
  bool _isVerified = false;
  bool _challengeReady = false;
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
      _challengeReady = false;
      _errorMessage = null;
    });

    try {
      final url = widget.apiUrl ?? '${ApiConfig.baseUrl}/auth/altcha-challenge';
      final response = await http.get(Uri.parse(url));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (mounted) {
          setState(() {
            _challengeData = data;
            _isLoading = false;
            _challengeReady = true;
          });
        }
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
        _challengeReady = false;
        _errorMessage = msg;
      });
      widget.onError?.call(msg);
    }
  }

  void _onCheckboxTapped() {
    if (_isSolving || _isVerified || !_challengeReady || _challengeData == null) return;
    _solveChallenge(_challengeData!);
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
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(_errorMessage!,
                  style: const TextStyle(color: Colors.red, fontSize: 13)),
            ),
            TextButton(
              onPressed: _loadChallenge,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    return _buildContainer(
      borderColor: _isVerified
          ? AppTheme.success.withValues(alpha: 0.5)
          : AppTheme.egyptianBlue.withValues(alpha: 0.2),
      child: InkWell(
        onTap: (_challengeReady && !_isSolving && !_isVerified) ? _onCheckboxTapped : null,
        borderRadius: BorderRadius.circular(8),
        child: Row(
          children: [
            // Checkbox area
            SizedBox(
              width: 24,
              height: 24,
              child: _isSolving
                  ? const Padding(
                      padding: EdgeInsets.all(2),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : _isVerified
                      ? Icon(Icons.check_box, color: AppTheme.success, size: 24)
                      : Icon(
                          Icons.check_box_outline_blank,
                          color: (_challengeReady && !_isLoading)
                              ? AppTheme.navyBlue.withValues(alpha: 0.6)
                              : AppTheme.navyBlue.withValues(alpha: 0.2),
                          size: 24,
                        ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                _isLoading
                    ? 'Loading...'
                    : _isSolving
                        ? 'Verifying...'
                        : _isVerified
                            ? 'Verified'
                            : 'I\'m not a robot',
                style: TextStyle(
                  color: _isVerified
                      ? AppTheme.success
                      : AppTheme.navyText.withValues(alpha: 0.7),
                  fontSize: 14,
                  fontWeight: _isVerified ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
            // Small branding
            Icon(
              Icons.shield_outlined,
              size: 16,
              color: AppTheme.navyBlue.withValues(alpha: 0.25),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContainer({required Color borderColor, required Widget child}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        border: Border.all(color: borderColor, width: 1.5),
        borderRadius: BorderRadius.circular(12),
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

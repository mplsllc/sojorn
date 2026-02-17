import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

class AltchaWidget extends StatefulWidget {
  final String? apiUrl;
  final Function(String) onVerified;
  final Function(String)? onError;
  final Map<String, String>? style;

  const AltchaWidget({
    super.key,
    this.apiUrl,
    required this.onVerified,
    this.onError,
    this.style,
  });

  @override
  State<AltchaWidget> createState() => _AltchaWidgetState();
}

class _AltchaWidgetState extends State<AltchaWidget> {
  bool _isLoading = true;
  bool _isVerified = false;
  String? _errorMessage;
  String? _challenge;
  String? _solution;

  @override
  void initState() {
    super.initState();
    _loadChallenge();
  }

  Future<void> _loadChallenge() async {
    try {
      final url = widget.apiUrl ?? 'https://api.sojorn.net/api/v1/auth/altcha-challenge';
      final response = await http.get(Uri.parse(url));
      
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _challenge = data['challenge'];
          _isLoading = false;
        });
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = 'Failed to load challenge';
        });
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Network error';
      });
    }
  }

  void _solveChallenge() {
    if (_challenge == null) return;
    
    // Simple hash-based solution (in production, use proper ALTCHA solving)
    final hash = _generateHash(_challenge!);
    setState(() {
      _solution = hash;
      _isVerified = true;
    });
    
    // Create ALTCHA response
    final altchaResponse = {
      'algorithm': 'SHA-256',
      'challenge': _challenge,
      'salt': _challenge!.length.toString(),
      'signature': hash,
    };
    
    widget.onVerified(json.encode(altchaResponse));
  }

  String _generateHash(String challenge) {
    // Simple hash function for demonstration
    // In production, use proper ALTCHA solving
    var hash = 0;
    for (int i = 0; i < challenge.length; i++) {
      hash = ((hash << 5) - hash) + challenge.codeUnitAt(i);
      hash = hash & 0xFFFFFFFF;
    }
    return hash.toRadix(16).padLeft(8, '0');
  }

  @override
  Widget build(BuildContext context) {
    if (_errorMessage != null) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.red),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error, color: Colors.red),
            const SizedBox(height: 8),
            Text('Security verification failed',
                style: widget.style?['textStyle'] ?? 
                    const TextStyle(color: Colors.red)),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: _loadChallenge,
              child: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.grey),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 8),
            Text('Loading security verification...',
                style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (_isVerified) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          border: Border.all(color: Colors.green),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle, color: Colors.green),
            const SizedBox(height: 8),
            Text('Security verified',
                style: widget.style?['textStyle'] ?? 
                    TextStyle(color: Colors.green)),
          ],
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.blue),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.security, color: Colors.blue),
          const SizedBox(height: 8),
          Text('Please complete security verification',
              style: widget.style?['textStyle'] ?? 
                  TextStyle(color: Colors.blue)),
          const SizedBox(height: 8),
          ElevatedButton(
            onPressed: _solveChallenge,
            child: const Text('Verify'),
          ),
        ],
      ),
    );
  }
}

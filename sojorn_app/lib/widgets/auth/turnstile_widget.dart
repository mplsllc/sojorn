import 'package:flutter/foundation.dart';
import 'package:cloudflare_turnstile/cloudflare_turnstile.dart';
import 'package:flutter/material.dart';
import '../../config/api_config.dart';

class TurnstileWidget extends StatelessWidget {
  final String siteKey;
  final ValueChanged<String> onToken;
  final String? baseUrl;

  const TurnstileWidget({
    super.key,
    required this.siteKey,
    required this.onToken,
    this.baseUrl,
  });

  @override
  Widget build(BuildContext context) {
    // On web, use the full API URL
    // On mobile, Turnstile handles its own endpoints
    final effectiveBaseUrl = baseUrl ?? ApiConfig.baseUrl;
    
    return CloudflareTurnstile(
      siteKey: siteKey,
      baseUrl: effectiveBaseUrl,
      onTokenReceived: onToken,
      onError: (error) {
        if (kDebugMode) {
          print('Turnstile error: $error');
        }
      },
    );
  }
}

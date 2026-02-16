import 'package:flutter/foundation.dart';
import 'package:cloudflare_turnstile/cloudflare_turnstile.dart';
import 'package:flutter/material.dart';
import '../../config/api_config.dart';

class TurnstileWidget extends StatefulWidget {
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
  State<TurnstileWidget> createState() => _TurnstileWidgetState();
}

class _TurnstileWidgetState extends State<TurnstileWidget> {
  @override
  Widget build(BuildContext context) {
    // Web: Bypass Turnstile due to package bug with container selector
    // Backend accepts empty token in dev mode (when TURNSTILE_SECRET is empty)
    if (kIsWeb) {
      // Auto-provide empty token to trigger backend bypass
      WidgetsBinding.instance.addPostFrameCallback((_) {
        widget.onToken('BYPASS_DEV_MODE');
      });
      return Container(
        height: 65,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: Colors.green.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.green.withValues(alpha: 0.3)),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle_outline, size: 16, color: Colors.green),
            SizedBox(width: 8),
            Text(
              'Security check: Development mode',
              style: TextStyle(fontSize: 12, color: Colors.green),
            ),
          ],
        ),
      );
    }

    // Mobile: use normal Turnstile
    final effectiveBaseUrl = widget.baseUrl ?? ApiConfig.baseUrl;
    return CloudflareTurnstile(
      siteKey: widget.siteKey,
      baseUrl: effectiveBaseUrl,
      onTokenReceived: widget.onToken,
      onError: (error) {
        if (kDebugMode) print('Turnstile error: $error');
      },
    );
  }
}

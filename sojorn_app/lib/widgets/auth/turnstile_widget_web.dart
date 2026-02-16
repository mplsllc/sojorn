import 'dart:ui_web' as ui_web;
import 'dart:html' as html;
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import '../../config/api_config.dart';

/// Web-compatible Turnstile widget that creates its own HTML container
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
  String? _token;
  bool _scriptLoaded = false;
  bool _rendered = false;
  late final String _viewId = 'turnstile_${widget.siteKey.hashCode}_${DateTime.now().millisecondsSinceEpoch}';
  html.DivElement? _container;

  @override
  void initState() {
    super.initState();
    if (kIsWeb) {
      _loadTurnstileScript();
    }
  }

  void _loadTurnstileScript() {
    // Check if script already loaded
    if (html.document.querySelector('script[src*="turnstile"]') != null) {
      _scriptLoaded = true;
      return;
    }

    final script = html.ScriptElement()
      ..src = 'https://challenges.cloudflare.com/turnstile/v0/api.js'
      ..async = true
      ..defer = true;
    
    script.onLoad.listen((_) {
      if (mounted) {
        setState(() => _scriptLoaded = true);
      }
    });

    html.document.head?.append(script);
  }

  void _renderTurnstile() {
    if (!kIsWeb || !_scriptLoaded || _rendered) return;
    
    final turnstile = html.window['turnstile'];
    if (turnstile == null) return;

    try {
      turnstile.callMethod('render', [
        _container,
        {
          'sitekey': widget.siteKey,
          'callback': (String token) {
            if (mounted) {
              setState(() => _token = token);
              widget.onToken(token);
            }
          },
          'theme': 'light',
        }
      ]);
      _rendered = true;
    } catch (e) {
      if (kDebugMode) {
        print('Turnstile render error: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!kIsWeb) {
      // On mobile, show a placeholder or use native implementation
      return Container(
        height: 65,
        alignment: Alignment.center,
        child: const Text('Security verification'),
      );
    }

    if (!_scriptLoaded) {
      return Container(
        height: 65,
        alignment: Alignment.center,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(height: 8),
            Text(
              'Loading security check...',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // Use HtmlElementView for the actual Turnstile
    return SizedBox(
      height: 65,
      child: HtmlElementView(
        viewType: _viewId,
        onPlatformViewCreated: (_) {
          // The container is created in the platform view factory
          Future.delayed(const Duration(milliseconds: 100), _renderTurnstile);
        },
      ),
    );
  }

  @override
  void didUpdateWidget(TurnstileWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (kIsWeb && _scriptLoaded && !_rendered) {
      Future.delayed(const Duration(milliseconds: 100), _renderTurnstile);
    }
  }
}

/// Register the platform view factory for web
void registerTurnstileFactory() {
  if (!kIsWeb) return;
  
  ui_web.platformViewRegistry.registerViewFactory(
    'turnstile',
        (int viewId, {Object? params}) {
      final div = html.DivElement()
        ..id = 'turnstile-container-$viewId'
        ..style.width = '100%'
        ..style.height = '100%';
      return div;
    },
  );
}

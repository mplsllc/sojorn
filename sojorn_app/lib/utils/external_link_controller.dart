import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/api_service.dart';
import '../theme/tokens.dart';
import '../widgets/safety_redirect_sheet.dart';

/// External Link Traffic Controller
///
/// Provides safe URL routing using the backend safe_domains table.
/// Domains in the approved list open without safety warnings.
/// All other domains show a confirmation sheet before opening.
///
/// The safe domains list is fetched from the backend API and cached locally.
class ExternalLinkController {
  /// Cached safe domains fetched from the backend
  static List<String> _safeDomains = [];
  static bool _loaded = false;
  static DateTime? _lastFetched;

  /// Fetch safe domains from the backend API and cache them.
  /// Called once on app startup or when needed.
  static Future<void> loadSafeDomains() async {
    try {
      final data = await ApiService.instance.callGoApi(
        '/safe-domains',
        method: 'GET',
      );
      final domains = data['domains'] as List<dynamic>? ?? [];
      _safeDomains = domains
          .map((d) => (d['domain'] as String? ?? '').toLowerCase())
          .where((d) => d.isNotEmpty)
          .toList();
      _loaded = true;
      _lastFetched = DateTime.now();
      if (kDebugMode) {
        print('[SafeDomains] Loaded ${_safeDomains.length} safe domains from backend');
      }
    } catch (e) {
      if (kDebugMode) {
        print('[SafeDomains] Failed to fetch safe domains: $e');
      }
      // Keep any previously cached domains
    }
  }

  /// Handles URL routing with safety checks against the backend safe_domains list.
  ///
  /// [context] - BuildContext for showing dialogs/sheets
  /// [url] - The URL to open
  ///
  /// Flow:
  /// 1. Ensure safe domains are loaded (lazy load if needed)
  /// 2. Parse the URL and extract the host (domain)
  /// 3. Check if host matches any safe domain (suffix match)
  /// 4. If safe: launch immediately
  /// 5. If not safe: show SafetyRedirectSheet for user confirmation
  static Future<void> handleUrl(BuildContext context, String url) async {
    if (url.trim().isEmpty) return;

    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return;

    // Lazy load safe domains if not yet loaded or stale (> 1 hour)
    if (!_loaded || _lastFetched == null ||
        DateTime.now().difference(_lastFetched!).inHours >= 1) {
      await loadSafeDomains();
    }

    final String host = uri.host.toLowerCase();

    if (_isSafe(host)) {
      await _launchUrl(context, uri);
    } else {
      _showSafetyRedirectSheet(context, uri);
    }
  }

  /// Check if the domain matches any safe domain (suffix match).
  /// e.g., "news.bbc.co.uk" matches "bbc.co.uk"
  static bool _isSafe(String host) {
    return _safeDomains.any((domain) =>
        host == domain || host.endsWith('.$domain'));
  }

  /// Launch URL using url_launcher
  static Future<void> _launchUrl(BuildContext context, Uri uri) async {
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      } else {
        _showError(context, 'Could not open link.');
      }
    } catch (e) {
      _showError(context, 'Error opening link: $e');
    }
  }

  /// Show the Safety Redirect Sheet for unknown domains
  static void _showSafetyRedirectSheet(BuildContext context, Uri uri) {
    showModalBottomSheet(
      context: context,
      backgroundColor: SojornColors.transparent,
      builder: (context) => SafetyRedirectSheet(
        url: uri.toString(),
        domain: uri.host,
      ),
    );
  }

  /// Show error snackbar
  static void _showError(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: SojornColors.destructive,
      ),
    );
  }

  /// Check if a domain is currently in the safe list
  static bool isWhitelisted(String domain) {
    return _isSafe(domain.toLowerCase());
  }

  /// Force reload of safe domains from backend
  static Future<void> refresh() async {
    await loadSafeDomains();
  }

  /// Get all cached safe domains (for debugging)
  static List<String> getWhitelist() {
    return List.unmodifiable(_safeDomains);
  }
}

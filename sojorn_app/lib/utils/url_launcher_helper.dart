// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import 'external_link_controller.dart';
import 'snackbar_ext.dart';

/// Helper class for safely launching URLs with user warnings for unknown sites.
/// 
/// Uses [ExternalLinkController] for the safe domains list (fetched from backend).
class UrlLauncherHelper {
  /// Check if a URL is from a known safe domain.
  /// Delegates to [ExternalLinkController] which manages the backend-synced list.
  static bool isKnownSafeDomain(String url) {
    try {
      final uri = Uri.parse(url.startsWith('http') ? url : 'https://$url');
      final host = uri.host.toLowerCase();
      return ExternalLinkController.isWhitelisted(host);
    } catch (e) {
      return false;
    }
  }

  /// Safely launch a URL with user confirmation for unknown sites
  static Future<void> launchUrlSafely(
    BuildContext context,
    String url, {
    bool forceWarning = false,
  }) async {
    // Validate URL scheme to prevent shell escaping
    try {
      final uri = Uri.parse(url.startsWith('http') ? url : 'https://$url');
      if (!['http:', 'https:'].contains(uri.scheme)) {
        context.showError('Invalid URL scheme. Only HTTP and HTTPS URLs are allowed.');
        return;
      }
    } catch (e) {
      context.showError('Invalid URL format.');
      return;
    }

    final isSafe = isKnownSafeDomain(url);

    // Show warning dialog for unknown sites
    if (!isSafe || forceWarning) {
      final shouldLaunch = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('External Link'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'You are about to visit an external website:',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppTheme.egyptianBlue.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  url,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              if (!isSafe) ...[
                Row(
                  children: [
                    Icon(
                      Icons.warning_amber,
                      color: SojornColors.nsfwWarningIcon,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'This site is not recognized as a known safe website. Proceed with caution.',
                        style: TextStyle(
                          fontSize: 13,
                          color: SojornColors.nsfwWarningIcon,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
              ],
              const Text(
                'Always be careful when visiting external links and never share your password or personal information.',
                style: TextStyle(fontSize: 13),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: isSafe ? AppTheme.royalPurple : SojornColors.nsfwWarningIcon,
              ),
              child: const Text('Continue'),
            ),
          ],
        ),
      );

      if (shouldLaunch != true) return;
    }

    // Launch the URL
    try {
      final uri = Uri.parse(url.startsWith('http') ? url : 'https://$url');
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      } else {
        if (context.mounted) {
          context.showError('Could not open link: $url');
        }
      }
    } catch (e) {
      if (context.mounted) {
        context.showError('Error opening link: ${e.toString()}');
      }
    }
  }
}

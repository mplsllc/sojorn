// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';

/// Safety Redirect Sheet
///
/// A clean, friendly modal bottom sheet that reminds users to be careful
/// when visiting external links.
class SafetyRedirectSheet extends StatelessWidget {
  final String url;
  final String domain;

  const SafetyRedirectSheet({
    super.key,
    required this.url,
    required this.domain,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final accentColor = theme.primaryColor;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: theme.scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(24),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Icon(
              CupertinoIcons.arrow_up_right_square,
              size: 56,
              color: theme.iconTheme.color?.withValues(alpha: 0.7) ??
                  SojornColors.textDisabled,
            ),
            const SizedBox(height: 20),

            // Title
            Text(
              'Leaving sojorn',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),

            // Body
            Text(
              'This link is taking you to an external website.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color:
                    theme.textTheme.bodyMedium?.color?.withValues(alpha: 0.8),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),

            // Domain (bolded)
            Text(
              domain,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: accentColor,
              ),
            ),
            const SizedBox(height: 8),

            // Full URL (truncated, small)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                _truncateUrl(url),
                style: theme.textTheme.bodySmall?.copyWith(
                  color:
                      theme.textTheme.bodySmall?.color?.withValues(alpha: 0.7),
                  fontSize: 11,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: 20),

            // Gentle reminder
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.cardColor,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: theme.dividerColor.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    CupertinoIcons.hand_raised,
                    color: theme.iconTheme.color?.withValues(alpha: 0.6) ??
                        SojornColors.textDisabled,
                    size: 18,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Only proceed if you trust this source.',
                      style: TextStyle(
                        color: theme.textTheme.bodyMedium?.color
                            ?.withValues(alpha: 0.8),
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Actions
            Row(
              children: [
                // Cancel Button - Stay Here
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: accentColor),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: Text(
                      'Stay Here',
                      style: TextStyle(
                        color: accentColor,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),

                // Confirm Button - Visit Link
                Expanded(
                  child: ElevatedButton(
                    onPressed: () async {
                      Navigator.of(context).pop();
                      final uri = Uri.parse(url);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: theme.scaffoldBackgroundColor,
                      foregroundColor: theme.textTheme.bodyMedium?.color,
                      elevation: 0,
                      side: BorderSide(color: theme.dividerColor),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text(
                      'Visit Link',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Truncate URL for display while keeping the domain visible
  String _truncateUrl(String url) {
    if (url.length <= 60) return url;
    return '${url.substring(0, 27)}...${url.substring(url.length - 25)}';
  }
}

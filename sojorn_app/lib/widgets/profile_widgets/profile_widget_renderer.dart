// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import '../../models/profile_widgets.dart';
import '../../theme/tokens.dart';

/// Renders a list of profile widgets based on a ProfileLayout.
/// Used both on the profile editor preview and the public profile view.
class ProfileWidgetRenderer extends StatelessWidget {
  final ProfileLayout layout;
  final bool isOwnProfile;

  const ProfileWidgetRenderer({
    super.key,
    required this.layout,
    this.isOwnProfile = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = ProfileTheme.getThemeByName(layout.theme);
    final enabledWidgets = layout.widgets
        .where((w) => w.isEnabled)
        .toList()
      ..sort((a, b) => a.order.compareTo(b.order));

    if (enabledWidgets.isEmpty) {
      if (isOwnProfile) {
        return Padding(
          padding: const EdgeInsets.all(SojornSpacing.lg),
          child: Center(
            child: Column(
              children: [
                Icon(Icons.widgets_outlined, size: 40, color: SojornColors.textDisabled),
                const SizedBox(height: 8),
                Text('Customize your profile with widgets',
                    style: TextStyle(color: SojornColors.textDisabled, fontSize: 13)),
              ],
            ),
          ),
        );
      }
      return const SizedBox.shrink();
    }

    return Container(
      color: theme.backgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: SojornSpacing.md, vertical: SojornSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: enabledWidgets
            .map((w) => Padding(
                  padding: const EdgeInsets.only(bottom: SojornSpacing.sm),
                  child: _buildWidget(context, w, theme),
                ))
            .toList(),
      ),
    );
  }

  Widget _buildWidget(BuildContext context, ProfileWidget widget, ProfileTheme theme) {
    switch (widget.type) {
      case ProfileWidgetType.quote:
        return _QuoteWidget(config: widget.config, theme: theme);
      case ProfileWidgetType.customText:
        return _CustomTextWidget(config: widget.config, theme: theme);
      case ProfileWidgetType.pinnedPosts:
        return _PlaceholderWidget(type: widget.type, theme: theme);
      case ProfileWidgetType.musicWidget:
        return _PlaceholderWidget(type: widget.type, theme: theme);
      case ProfileWidgetType.photoGrid:
        return _PlaceholderWidget(type: widget.type, theme: theme);
      case ProfileWidgetType.socialLinks:
        return _SocialLinksWidget(config: widget.config, theme: theme);
      case ProfileWidgetType.bio:
        return _BioWidget(config: widget.config, theme: theme);
      case ProfileWidgetType.stats:
        return _PlaceholderWidget(type: widget.type, theme: theme);
      case ProfileWidgetType.beaconActivity:
        return _PlaceholderWidget(type: widget.type, theme: theme);
      case ProfileWidgetType.featuredFriends:
        return _PlaceholderWidget(type: widget.type, theme: theme);
    }
  }
}

class _QuoteWidget extends StatelessWidget {
  final Map<String, dynamic> config;
  final ProfileTheme theme;
  const _QuoteWidget({required this.config, required this.theme});

  @override
  Widget build(BuildContext context) {
    final text = config['text'] as String? ?? 'Add a quote...';
    final author = config['author'] as String? ?? '';

    return Container(
      padding: const EdgeInsets.all(SojornSpacing.md),
      decoration: BoxDecoration(
        color: theme.accentColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(SojornRadii.card),
        border: Border(
          left: BorderSide(color: theme.accentColor, width: 3),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('"$text"',
              style: TextStyle(
                color: theme.textColor,
                fontSize: 15,
                fontStyle: FontStyle.italic,
                height: 1.5,
              )),
          if (author.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('— $author',
                style: TextStyle(
                  color: theme.textColor.withValues(alpha: 0.6),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                )),
          ],
        ],
      ),
    );
  }
}

class _CustomTextWidget extends StatelessWidget {
  final Map<String, dynamic> config;
  final ProfileTheme theme;
  const _CustomTextWidget({required this.config, required this.theme});

  @override
  Widget build(BuildContext context) {
    final title = config['title'] as String? ?? '';
    final body = config['body'] as String? ?? 'Write something...';

    return Container(
      padding: const EdgeInsets.all(SojornSpacing.md),
      decoration: BoxDecoration(
        color: theme.backgroundColor,
        borderRadius: BorderRadius.circular(SojornRadii.card),
        border: Border.all(color: theme.primaryColor.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title.isNotEmpty) ...[
            Text(title,
                style: TextStyle(
                  color: theme.textColor,
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                )),
            const SizedBox(height: 6),
          ],
          Text(body,
              style: TextStyle(
                color: theme.textColor.withValues(alpha: 0.8),
                fontSize: 13,
                height: 1.5,
              )),
        ],
      ),
    );
  }
}

class _BioWidget extends StatelessWidget {
  final Map<String, dynamic> config;
  final ProfileTheme theme;
  const _BioWidget({required this.config, required this.theme});

  @override
  Widget build(BuildContext context) {
    final bio = config['text'] as String? ?? '';
    if (bio.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(SojornSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SojornRadii.card),
        color: theme.backgroundColor,
      ),
      child: Text(bio,
          style: TextStyle(
            color: theme.textColor,
            fontSize: 14,
            height: 1.5,
          )),
    );
  }
}

class _SocialLinksWidget extends StatelessWidget {
  final Map<String, dynamic> config;
  final ProfileTheme theme;
  const _SocialLinksWidget({required this.config, required this.theme});

  @override
  Widget build(BuildContext context) {
    final links = (config['links'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    if (links.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(SojornSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SojornRadii.card),
        color: theme.backgroundColor,
        border: Border.all(color: theme.primaryColor.withValues(alpha: 0.1)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: links.map((link) {
          final label = link['label'] as String? ?? 'Link';
          return Chip(
            avatar: Icon(Icons.link, size: 14, color: theme.accentColor),
            label: Text(label, style: TextStyle(fontSize: 12, color: theme.textColor)),
            backgroundColor: theme.accentColor.withValues(alpha: 0.08),
          );
        }).toList(),
      ),
    );
  }
}

/// Placeholder for widget types that need more data integration.
class _PlaceholderWidget extends StatelessWidget {
  final ProfileWidgetType type;
  final ProfileTheme theme;
  const _PlaceholderWidget({required this.type, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(SojornSpacing.md),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SojornRadii.card),
        color: theme.backgroundColor,
        border: Border.all(color: theme.primaryColor.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Icon(type.icon, size: 20, color: theme.accentColor),
          const SizedBox(width: 10),
          Text(type.displayName,
              style: TextStyle(color: theme.textColor, fontSize: 13, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }
}

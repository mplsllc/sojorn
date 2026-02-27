// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../models/profile.dart';
import '../../models/profile_privacy_settings.dart';
import '../../providers/api_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/theme_provider.dart' as app_theme;
import '../../services/image_upload_service.dart';
import '../../services/notification_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'privacy_dashboard_screen.dart';
import '../home/full_screen_shell.dart';
import '../../widgets/media/signed_media_image.dart';
import '../../widgets/media/sojorn_avatar.dart';
import '../../widgets/sojorn_input.dart';
import '../../services/api_service.dart';
import '../../utils/snackbar_ext.dart';
import '../../widgets/sojorn_text_area.dart';
import 'follow_requests_screen.dart';
import 'blocked_users_screen.dart';
import 'category_settings_screen.dart';
import '../compose/image_editor_screen.dart';
import '../../models/sojorn_media_result.dart';
import '../security/encryption_hub_screen.dart';
import '../settings/accessibility_settings_screen.dart';
import '../settings/mfa_setup_screen.dart';
import '../settings/violations_screen.dart';
import '../settings/report_history_screen.dart';
import '../../widgets/neighborhood/neighborhood_picker_sheet.dart';
import '../../widgets/desktop/desktop_dialog_helper.dart';
import '../../widgets/desktop/desktop_slide_panel.dart';
import '../../models/trust_tier.dart';

class ProfileSettingsScreen extends ConsumerStatefulWidget {
  final Profile? profile;
  final ProfilePrivacySettings? settings;

  const ProfileSettingsScreen({super.key, this.profile, this.settings});

  @override
  ConsumerState<ProfileSettingsScreen> createState() => _ProfileSettingsScreenState();
}

class ProfileSettingsResult {
  final Profile profile;
  final ProfilePrivacySettings settings;
  ProfileSettingsResult({required this.profile, required this.settings});
}

class _ProfileSettingsScreenState extends ConsumerState<ProfileSettingsScreen> {
  final ImagePicker _imagePicker = ImagePicker();
  final ImageUploadService _imageUploadService = ImageUploadService();
  bool _isAvatarUploading = false;
  bool _isBannerUploading = false;
  bool _nsfwSectionExpanded = false;
  Map<String, dynamic>? _myNeighborhood;
  bool _loadingNeighborhood = true;

  @override
  void initState() {
    super.initState();
    _loadMyNeighborhood();
  }

  Future<void> _loadMyNeighborhood() async {
    try {
      final data = await ApiService.instance.getMyNeighborhood();
      if (mounted) setState(() {
        _myNeighborhood = data;
        _loadingNeighborhood = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingNeighborhood = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(settingsProvider);
    final profile = state.profile;
    
    final isDesktop = MediaQuery.of(context).size.width >= 900;

    if (state.isLoading && profile == null) {
      if (isDesktop) {
        return Scaffold(
          appBar: AppBar(title: const Text('Settings'), leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop())),
          body: const Center(child: CircularProgressIndicator()),
        );
      }
      return const FullScreenShell(
        titleText: 'Settings',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (profile == null) {
      if (isDesktop) {
        return Scaffold(
          appBar: AppBar(title: const Text('Settings'), leading: IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.of(context).pop())),
          body: const Center(child: Text('Failed to load profile')),
        );
      }
      return const FullScreenShell(
        titleText: 'Settings',
        body: Center(child: Text('Failed to load profile')),
      );
    }

    final body = SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildProfileHeader(profile),
            Padding(
              padding: const EdgeInsets.all(AppTheme.spacingLg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                   _buildHarmonyInsight(state),
                   const SizedBox(height: AppTheme.spacingLg),
                   
                   _buildSection(
                     title: 'Account',
                     subtitle: 'Your profile, data, and privacy',
                     children: [
                       _buildEditTile(
                         icon: Icons.person_outline,
                         title: 'Profile',
                         subtitle: 'Name, handle, bio, avatar',
                         onTap: () => _showIdentityEditor(profile),
                       ),
                       _buildEditTile(
                         icon: Icons.circle_outlined,
                         title: 'Status',
                         subtitle: profile.statusText?.isNotEmpty == true
                             ? profile.statusText!
                             : 'Set a status — "at the coffee shop"',
                         onTap: () => _showStatusEditor(profile),
                       ),
                       _buildEditTile(
                         icon: Icons.lock,
                         title: 'Encryption & Backup',
                         subtitle: 'Manage your encryption keys',
                         onTap: () {
                           if (isDesktop) {
                             openDesktopSlidePanel(context, width: 480, child: const EncryptionHubScreen());
                           } else {
                             Navigator.of(context).push(MaterialPageRoute(builder: (_) => const EncryptionHubScreen()));
                           }
                         },
                       ),
                       _buildEditTile(
                         icon: Icons.security,
                         title: 'Two-Factor Authentication',
                         subtitle: 'Protect your account with TOTP',
                         onTap: () {
                           if (isDesktop) {
                             openDesktopSlidePanel(context, width: 480, child: const MFASetupScreen());
                           } else {
                             Navigator.of(context).push(MaterialPageRoute(builder: (_) => const MFASetupScreen()));
                           }
                         },
                       ),
                       _buildEditTile(
                         icon: Icons.interests_outlined,
                         title: 'Content Interests',
                         subtitle: 'Topics used to personalize your feed',
                         onTap: () {
                           if (isDesktop) {
                             openDesktopSlidePanel(context, width: 480, child: const CategoryDiscoveryScreen());
                           } else {
                             Navigator.of(context).push(MaterialPageRoute(builder: (_) => const CategoryDiscoveryScreen()));
                           }
                         },
                       ),
                       _buildEditTile(
                         icon: Icons.remove_circle_outline,
                         title: 'Account Removal',
                         subtitle: 'Deactivate, delete, or erase your account',
                         color: SojornColors.destructive,
                         onTap: () => _showAccountRemovalSheet(),
                       ),
                     ],
                   ),

                   const SizedBox(height: AppTheme.spacingLg),
                   _buildSection(
                     title: 'The Circle',
                     subtitle: 'Social harmony & visibility',
                     children: [
                       _buildEditTile(
                         icon: Icons.person_add_alt_1_outlined,
                         title: 'Follow Requests',
                         onTap: () {
                           if (isDesktop) {
                             openDesktopDialog(context, width: 500, child: const FollowRequestsScreen());
                           } else {
                             Navigator.of(context).push(MaterialPageRoute(builder: (_) => const FollowRequestsScreen()));
                           }
                         },
                       ),
                       _buildEditTile(
                         icon: Icons.block_flipped,
                         title: 'Blocked',
                         onTap: () {
                           if (isDesktop) {
                             openDesktopDialog(context, width: 500, child: const BlockedUsersScreen());
                           } else {
                             Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BlockedUsersScreen()));
                           }
                         },
                       ),
                       _buildEditTile(
                         icon: Icons.visibility_outlined,
                         title: 'Privacy Gates',
                         onTap: () => _showPrivacyEditor(),
                       ),
                       _buildEditTile(
                         icon: Icons.dashboard_outlined,
                         title: 'Privacy Dashboard',
                         onTap: () {
                           if (isDesktop) {
                             openDesktopSlidePanel(context, width: 520, child: const PrivacyDashboardScreen());
                           } else {
                             Navigator.of(context).push(MaterialPageRoute(builder: (_) => const PrivacyDashboardScreen()));
                           }
                         },
                       ),
                     ],
                   ),
                   const SizedBox(height: AppTheme.spacingLg),
                   _buildSection(
                     title: 'Your Neighborhood',
                     subtitle: 'Local community & boards',
                     children: [
                       _buildNeighborhoodTile(),
                     ],
                   ),

                   const SizedBox(height: AppTheme.spacingLg),
                   _buildSection(
                     title: 'Focus Gates',
                     subtitle: 'Notification & Aesthetic control',
                     children: [
                       _buildEditTile(
                         icon: Icons.notifications_none_outlined,
                         title: 'Notification Gates',
                         onTap: () => _showNotificationEditor(),
                       ),
                       _buildEditTile(
                         icon: Icons.timer_outlined,
                         title: 'Post Lifespan',
                         onTap: () => _showTtlEditor(),
                       ),
                       _buildEditTile(
                         icon: Icons.palette_outlined,
                         title: 'Vibe & Aesthetic',
                         onTap: () => _showAestheticEditor(),
                       ),
                     ],
                   ),

                   const SizedBox(height: AppTheme.spacingLg),
                   _buildSection(
                     title: 'Preferences',
                     subtitle: 'App behavior & accessibility',
                     children: [
                       _buildEditTile(
                         icon: Icons.language,
                         title: 'Language',
                         subtitle: 'English (US)',
                         onTap: () => context.showInfo('Language settings coming soon'),
                       ),
                       _buildEditTile(
                         icon: Icons.accessibility_new_outlined,
                         title: 'Accessibility',
                         subtitle: 'Text size, motion, screen reader',
                         onTap: () {
                           if (isDesktop) {
                             openDesktopSlidePanel(context, width: 480, child: const AccessibilitySettingsScreen());
                           } else {
                             Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AccessibilitySettingsScreen()));
                           }
                         },
                       ),
                       _buildEditTile(
                         icon: Icons.link,
                         title: 'Connected Accounts',
                         subtitle: 'Linked services and sign-in methods',
                         onTap: () => context.showInfo('Connected accounts coming soon'),
                       ),
                     ],
                   ),

                   const SizedBox(height: AppTheme.spacingLg),
                   _buildSection(
                     title: 'Safety & Reports',
                     subtitle: 'Violations, appeals, and report history',
                     children: [
                       _buildEditTile(
                         icon: Icons.gavel_outlined,
                         title: 'Violations & Appeals',
                         subtitle: 'View violations and submit appeals',
                         onTap: () {
                           if (isDesktop) {
                             openDesktopSlidePanel(context, width: 480, child: const ViolationsScreen());
                           } else {
                             Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ViolationsScreen()));
                           }
                         },
                       ),
                       _buildEditTile(
                         icon: Icons.flag_outlined,
                         title: 'Report History',
                         subtitle: 'Track reports you have submitted',
                         onTap: () {
                           if (isDesktop) {
                             openDesktopSlidePanel(context, width: 480, child: const ReportHistoryScreen());
                           } else {
                             Navigator.of(context).push(MaterialPageRoute(builder: (_) => const ReportHistoryScreen()));
                           }
                         },
                       ),
                     ],
                   ),

                   const SizedBox(height: AppTheme.spacingLg * 2),
                   _buildLogoutButton(),
                   
                   const SizedBox(height: AppTheme.spacingLg),
                   _buildFooter(),

                   const SizedBox(height: AppTheme.spacingLg * 2),
                   _buildNsfwSection(state),
                ],
              ),
            ),
          ],
        ),
      );

    if (isDesktop) {
      return Scaffold(
        backgroundColor: AppTheme.scaffoldBg,
        appBar: AppBar(
          backgroundColor: AppTheme.scaffoldBg,
          elevation: 0,
          surfaceTintColor: SojornColors.transparent,
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
          title: Text('Settings', style: TextStyle(color: AppTheme.textPrimary, fontSize: 18, fontWeight: FontWeight.w600)),
        ),
        body: body,
      );
    }

    return FullScreenShell(
      titleText: 'Settings',
      body: body,
    );
  }

  Widget _buildProfileHeader(Profile profile) {
    const bannerHeight = 140.0;
    const avatarSize = 80.0;
    // Avatar is vertically centered on the banner's bottom edge
    const avatarTop = bannerHeight - avatarSize / 2;
    const avatarOverflow = avatarSize / 2; // how far avatar extends below banner

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Stack(
          clipBehavior: Clip.none,
          children: [
            // Banner
            GestureDetector(
              onTap: () => _pickMedia(isBanner: true),
              child: Container(
                height: bannerHeight,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: AppTheme.egyptianBlue.withValues(alpha: 0.1),
                ),
                child: _isBannerUploading
                  ? const Center(child: CircularProgressIndicator())
                  : profile.coverUrl != null
                    ? SignedMediaImage(url: profile.coverUrl!, fit: BoxFit.cover)
                    : Center(child: Icon(Icons.add_photo_alternate_outlined, color: AppTheme.egyptianBlue.withValues(alpha: 0.5), size: 36)),
              ),
            ),
            // Camera button — top-right of banner, above the avatar overlap zone
            Positioned(
              top: 10,
              right: 12,
              child: _buildGlassButton(
                onTap: () => _pickMedia(isBanner: true),
                icon: Icons.camera_alt_outlined,
              ),
            ),
            // Avatar — overlaps banner bottom edge
            Positioned(
              top: avatarTop,
              left: 24,
              child: GestureDetector(
                onTap: () => _pickMedia(isBanner: false),
                child: Stack(
                  children: [
                    if (_isAvatarUploading)
                      Container(
                        width: avatarSize,
                        height: avatarSize,
                        decoration: BoxDecoration(
                          color: AppTheme.queenPink,
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: AppTheme.scaffoldBg, width: 3),
                        ),
                        alignment: Alignment.center,
                        child: const CircularProgressIndicator(),
                      )
                    else
                      Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(22),
                          border: Border.all(color: AppTheme.scaffoldBg, width: 3),
                        ),
                        child: SojornAvatar(
                          displayName: profile.displayName ?? profile.handle ?? '?',
                          avatarUrl: profile.avatarUrl,
                          size: avatarSize,
                          borderRadius: 20,
                        ),
                      ),
                    Positioned(
                      bottom: 2,
                      right: 2,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: AppTheme.brightNavy,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppTheme.scaffoldBg, width: 2),
                        ),
                        child: const Icon(Icons.add_a_photo, size: 13, color: SojornColors.basicWhite),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
        // Space for the portion of the avatar that hangs below the banner
        SizedBox(height: avatarOverflow + 12),
      ],
    );
  }

  bool _isHarmonyExpanded = false;

  Widget _buildHarmonyInsight(SettingsState state) {
    final trust = state.trust;
    if (trust == null) return const SizedBox.shrink();

    return GestureDetector(
      onTap: () => setState(() => _isHarmonyExpanded = !_isHarmonyExpanded),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(AppTheme.spacingMd),
        decoration: BoxDecoration(
          color: AppTheme.royalPurple.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppTheme.royalPurple.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.royalPurple.withValues(alpha: 0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.spa_outlined, color: AppTheme.royalPurple),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Trust Level: ${trust.tier.displayName}', style: AppTheme.textTheme.labelMedium),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: LinearProgressIndicator(
                          value: (trust.harmonyScore / 100).clamp(0.0, 1.0).toDouble(),
                          backgroundColor: AppTheme.royalPurple.withValues(alpha: 0.1),
                          valueColor: AlwaysStoppedAnimation(AppTheme.royalPurple),
                          minHeight: 4,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Harmony Score: ${trust.harmonyScore}%',
                        style: AppTheme.textTheme.bodySmall?.copyWith(color: AppTheme.navyText.withValues(alpha: 0.6)),
                      ),
                    ],
                  ),
                ),
                Icon(
                  _isHarmonyExpanded ? Icons.expand_less : Icons.expand_more,
                  color: AppTheme.royalPurple.withValues(alpha: 0.5),
                ),
              ],
            ),
            AnimatedCrossFade(
              firstChild: const SizedBox.shrink(),
              secondChild: Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Divider(color: AppTheme.royalPurple.withValues(alpha: 0.1)),
                    const SizedBox(height: 8),
                    Text('Trust Tiers', style: AppTheme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    ...TrustTier.values.expand((t) => [
                      _buildTierRow(
                        '${t.emoji} ${t.displayName}',
                        '${t.minScore}–${t.maxScore}',
                        trust.tier == t,
                        '${t.postLimit} posts/day',
                      ),
                      const SizedBox(height: 4),
                    ]),
                    const SizedBox(height: 12),
                    Text('How to improve', style: AppTheme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 6),
                    _buildHarmonyTip(Icons.post_add, 'Post regularly and engage with others'),
                    _buildHarmonyTip(Icons.favorite_border, 'Get positive reactions on your content'),
                    _buildHarmonyTip(Icons.shield_outlined, 'Follow community guidelines'),
                  ],
                ),
              ),
              crossFadeState: _isHarmonyExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
              duration: const Duration(milliseconds: 200),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTierRow(String name, String range, bool isCurrent, String benefit) {
    return Row(
      children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            color: isCurrent ? AppTheme.royalPurple : AppTheme.navyText.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '$name ($range)',
          style: TextStyle(
            fontSize: 12,
            fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
            color: isCurrent ? AppTheme.royalPurple : AppTheme.navyText.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(benefit, style: TextStyle(fontSize: 11, color: AppTheme.navyText.withValues(alpha: 0.4)), overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Widget _buildHarmonyTip(IconData icon, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Icon(icon, size: 14, color: AppTheme.royalPurple.withValues(alpha: 0.6)),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: AppTheme.navyText.withValues(alpha: 0.6)))),
        ],
      ),
    );
  }

  Widget _buildSection({required String title, required String subtitle, required List<Widget> children}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: AppTheme.textTheme.headlineSmall),
        Text(subtitle, style: AppTheme.textTheme.labelSmall?.copyWith(color: AppTheme.navyText.withValues(alpha: 0.5))),
        const SizedBox(height: AppTheme.spacingMd),
        Container(
          decoration: BoxDecoration(
            color: AppTheme.isDark
                ? SojornColors.darkSurfaceElevated.withValues(alpha: 0.6)
                : SojornColors.basicWhite.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.isDark
                ? SojornColors.darkBorder.withValues(alpha: 0.3)
                : AppTheme.egyptianBlue.withValues(alpha: 0.1)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildEditTile({required IconData icon, required String title, required VoidCallback onTap, Color? color, String? subtitle}) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: color ?? AppTheme.navyBlue, size: 22),
      title: Text(title, style: AppTheme.textTheme.bodyLarge?.copyWith(color: color)),
      subtitle: subtitle != null
          ? Text(subtitle, style: AppTheme.textTheme.bodySmall?.copyWith(color: AppTheme.navyText.withValues(alpha: 0.45)))
          : null,
      trailing: Icon(Icons.chevron_right, color: AppTheme.egyptianBlue.withValues(alpha: 0.3)),
    );
  }

  Widget _buildGlassButton({required VoidCallback onTap, required IconData icon}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(8),
            color: SojornColors.basicWhite.withValues(alpha: 0.2),
            child: Icon(icon, color: SojornColors.basicWhite, size: 20),
          ),
        ),
      ),
    );
  }

  Widget _buildLogoutButton() {
    return SizedBox(
      width: double.infinity,
      child: TextButton.icon(
        onPressed: _signOut,
        icon: const Icon(Icons.logout),
        label: const Text('Sign Out'),
        style: TextButton.styleFrom(
          foregroundColor: AppTheme.error,
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  Widget _buildFooter() {
    return Center(
      child: Column(
        children: [
          Text('Sojorn Sanctuary', style: AppTheme.textTheme.labelMedium?.copyWith(color: AppTheme.navyText.withValues(alpha: 0.4))),
          Text('A product of MPLS LLC \u00a9 ${DateTime.now().year}', style: AppTheme.textTheme.labelSmall?.copyWith(color: AppTheme.navyText.withValues(alpha: 0.3))),
        ],
      ),
    );
  }

  // --- Neighborhood ---

  Widget _buildNeighborhoodTile() {
    if (_loadingNeighborhood) {
      return const ListTile(
        leading: SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2)),
        title: Text('Loading neighborhood...'),
      );
    }

    final hood = _myNeighborhood?['neighborhood'] as Map<String, dynamic>?;
    final canChange = _myNeighborhood?['can_change'] == true;
    final nextChange = _myNeighborhood?['next_change_allowed_at'] as String?;
    final name = hood?['name'] as String? ?? 'Not set';
    final city = hood?['city'] as String? ?? '';

    return ListTile(
      onTap: () => _showNeighborhoodChange(canChange, nextChange),
      leading: Icon(
        Icons.location_city_rounded,
        color: AppTheme.navyBlue,
        size: 22,
      ),
      title: Text(
        hood != null ? '$name, $city' : 'Set your neighborhood',
        style: AppTheme.textTheme.bodyLarge,
      ),
      subtitle: hood != null
          ? Text(
              canChange ? 'Tap to change' : 'Next change: ${_formatDateShort(nextChange ?? '')}',
              style: TextStyle(
                fontSize: 12,
                color: canChange
                    ? AppTheme.navyText.withValues(alpha: 0.5)
                    : SojornColors.nsfwWarningIcon.withValues(alpha: 0.8),
              ),
            )
          : null,
      trailing: Icon(Icons.chevron_right, color: AppTheme.egyptianBlue.withValues(alpha: 0.3)),
    );
  }

  Future<void> _showNeighborhoodChange(bool canChange, String? nextChange) async {
    if (!canChange && nextChange != null) {
      // Show warning that they can't change yet
      if (!mounted) return;
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          backgroundColor: AppTheme.cardSurface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Icon(Icons.schedule, color: SojornColors.nsfwWarningIcon, size: 24),
              const SizedBox(width: 10),
              const Expanded(child: Text('Change Cooldown')),
            ],
          ),
          content: Text(
            'You can only change your neighborhood once every 30 days.\n\nYour next change is available on ${_formatDateShort(nextChange)}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    if (!mounted) return;
    final result = await NeighborhoodPickerSheet.show(
      context,
      isChangeMode: true,
      nextChangeDate: nextChange,
    );
    if (result != null && mounted) {
      setState(() => _myNeighborhood = result);
    }
  }

  String _formatDateShort(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return isoDate;
    }
  }

  // --- Handlers ---

  void _showIdentityEditor(Profile profile) {
    final nameCtrl = TextEditingController(text: profile.displayName);
    final bioCtrl = TextEditingController(text: profile.bio);
    final webCtrl = TextEditingController(text: profile.website);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: SojornColors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: AppTheme.scaffoldBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 24, right: 24, top: 32,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Refine Identity', style: AppTheme.textTheme.headlineSmall),
            const SizedBox(height: 24),
            sojornInput(label: 'Display Name', controller: nameCtrl),
            const SizedBox(height: 16),
            sojornTextArea(label: 'Bio', controller: bioCtrl, minLines: 3),
            const SizedBox(height: 16),
            sojornInput(label: 'Website', controller: webCtrl),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () {
                ref.read(settingsProvider.notifier).updateProfile(profile.copyWith(
                  displayName: nameCtrl.text,
                  bio: bioCtrl.text,
                  website: webCtrl.text,
                ));
                Navigator.pop(context);
              },
              child: const Text('Save Changes'),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Widget _buildNsfwSection(dynamic state) {
    final userSettings = state.user;
    if (userSettings == null) return const SizedBox.shrink();

    // Calculate age from profile
    final profile = state.profile;
    bool isUnder18 = false;
    if (profile != null && profile.birthYear > 0) {
      final now = DateTime.now();
      int age = (now.year - profile.birthYear).toInt();
      if (now.month < profile.birthMonth) age--;
      isUnder18 = age < 18;
    }

    return Column(
      children: [
        // Expandable trigger — subtle, at the very bottom
        GestureDetector(
          onTap: () => setState(() => _nsfwSectionExpanded = !_nsfwSectionExpanded),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 20),
            decoration: BoxDecoration(
              color: AppTheme.cardSurface.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.08)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.shield_outlined,
                  size: 16,
                  color: AppTheme.textSecondary.withValues(alpha: 0.5),
                ),
                const SizedBox(width: 8),
                Text(
                  'Content Sensitivity Settings',
                  style: AppTheme.textTheme.labelSmall?.copyWith(
                    color: AppTheme.textSecondary.withValues(alpha: 0.5),
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(
                  _nsfwSectionExpanded ? Icons.expand_less : Icons.expand_more,
                  size: 16,
                  color: AppTheme.textSecondary.withValues(alpha: 0.5),
                ),
              ],
            ),
          ),
        ),

        // Expandable content
        if (_nsfwSectionExpanded) ...[
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              color: AppTheme.cardSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: AppTheme.nsfwWarningBorder),
            ),
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.visibility_off_outlined, size: 20, color: AppTheme.nsfwWarningIcon),
                    const SizedBox(width: 8),
                    Text('Content Filters', style: AppTheme.textTheme.headlineSmall),
                  ],
                ),
                const SizedBox(height: 4),
                Text(
                  'Control what content appears in your feed',
                  style: AppTheme.textTheme.labelSmall?.copyWith(color: AppTheme.textDisabled),
                ),
                const SizedBox(height: 16),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Show Sensitive Content (NSFW)'),
                  subtitle: Text(
                    isUnder18
                        ? 'You must be at least 18 years old to enable this feature. This is required by law in most jurisdictions.'
                        : 'Enable to see posts marked as sensitive (violence, mature themes, etc). Disabled by default.',
                  ),
                  value: userSettings.nsfwEnabled,
                  activeColor: AppTheme.nsfwWarningIcon,
                  onChanged: isUnder18
                      ? null
                      : (v) {
                          if (v) {
                            _showEnableNsfwConfirmation(userSettings);
                          } else {
                            ref.read(settingsProvider.notifier).updateUser(
                              userSettings.copyWith(nsfwEnabled: false, nsfwBlurEnabled: true),
                            );
                          }
                        },
                ),
                if (userSettings.nsfwEnabled) ...[
                  const Divider(height: 1),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Blur Sensitive Content'),
                    subtitle: const Text(
                      'When enabled, NSFW posts are blurred until you tap to reveal. Disable to show them without blur.',
                    ),
                    value: userSettings.nsfwBlurEnabled,
                    activeColor: AppTheme.nsfwWarningIcon,
                    onChanged: (v) {
                      if (!v) {
                        _showDisableBlurConfirmation(userSettings);
                      } else {
                        ref.read(settingsProvider.notifier).updateUser(
                          userSettings.copyWith(nsfwBlurEnabled: true),
                        );
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
        ],
        const SizedBox(height: AppTheme.spacingLg),
      ],
    );
  }

  Future<void> _showEnableNsfwConfirmation(dynamic userSettings) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppTheme.nsfwWarningIcon, size: 28),
            const SizedBox(width: 10),
            const Expanded(child: Text('Enable Sensitive Content')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SojornColors.destructive.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: SojornColors.destructive.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.eighteen_up_rating, color: SojornColors.destructive, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'You must be 18 or older to enable this feature.',
                      style: TextStyle(
                        color: SojornColors.destructive,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'By enabling NSFW content you acknowledge:',
              style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
            const SizedBox(height: 10),
            _buildBulletPoint('You will see content that may include nudity, violence, or mature themes from people you follow.'),
            _buildBulletPoint('This is NOT a "free for all" — all content is AI-moderated. Hardcore pornography, extreme violence, and illegal content are never permitted.'),
            _buildBulletPoint('Repeatedly posting improperly labeled content will result in warnings and potential account action.'),
            _buildBulletPoint('Blur will be enabled by default. You can disable it separately.'),
            _buildBulletPoint('NSFW content will only appear from accounts you follow — never in search, trending, or recommendations.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.nsfwWarningIcon,
              foregroundColor: SojornColors.basicWhite,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('I\'m 18+ — Enable'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      ref.read(settingsProvider.notifier).updateUser(
        userSettings.copyWith(nsfwEnabled: true, nsfwBlurEnabled: true),
      );
    }
  }

  Future<void> _showDisableBlurConfirmation(dynamic userSettings) async {
    final confirmed = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppTheme.cardSurface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.visibility_outlined, color: AppTheme.nsfwWarningIcon, size: 28),
            const SizedBox(width: 10),
            const Expanded(child: Text('Disable Content Blur')),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SojornColors.destructive.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: SojornColors.destructive.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.eighteen_up_rating, color: SojornColors.destructive, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'You must be 18 or older. This cannot be undone without re-enabling blur.',
                      style: TextStyle(
                        color: SojornColors.destructive,
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Disabling blur means sensitive content will be shown without any overlay or warning. This includes:',
              style: TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 10),
            _buildBulletPoint('Nudity, suggestive imagery, and mature themes will display fully visible in your feed.'),
            _buildBulletPoint('Violence, blood, and graphic content (rated 5 and under) will appear unblurred.'),
            _buildBulletPoint('You can re-enable blur at any time from this settings page.'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Keep Blur On', style: TextStyle(color: AppTheme.textSecondary)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: SojornColors.destructive,
              foregroundColor: SojornColors.basicWhite,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('I Understand — Disable Blur'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      ref.read(settingsProvider.notifier).updateUser(
        userSettings.copyWith(nsfwBlurEnabled: false),
      );
    }
  }

  Widget _buildBulletPoint(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Container(
              width: 5, height: 5,
              decoration: BoxDecoration(
                color: AppTheme.nsfwWarningIcon,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.4)),
          ),
        ],
      ),
    );
  }

  void _showPrivacyEditor() {
    final state = ref.read(settingsProvider);
    final privacy = state.privacy;
    if (privacy == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: SojornColors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: AppTheme.scaffoldBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Privacy Gates', style: AppTheme.textTheme.headlineSmall),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('Private Profile'),
              subtitle: const Text('Only followers can see your posts and activity'),
              value: privacy.isPrivate,
              onChanged: (v) => ref.read(settingsProvider.notifier).updatePrivacy(privacy.copyWith(isPrivate: v)),
            ),
            const SizedBox(height: 32),
            const Text('Default Post Visibility', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'public', label: Text('Public')),
                ButtonSegment(value: 'followers', label: Text('Circle')),
                ButtonSegment(value: 'private', label: Text('Self')),
              ],
              selected: {privacy.defaultVisibility},
              onSelectionChanged: (set) => ref.read(settingsProvider.notifier).updatePrivacy(privacy.copyWith(defaultVisibility: set.first)),
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  void _showStatusEditor(Profile profile) {
    final ctrl = TextEditingController(text: profile.statusText ?? '');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: SojornColors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: BoxDecoration(
            color: AppTheme.scaffoldBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Your Status', style: AppTheme.textTheme.headlineSmall),
              const SizedBox(height: 4),
              Text(
                'A short line that shows on your profile — tell people what you\'re up to.',
                style: AppTheme.bodyMedium.copyWith(
                    color: AppTheme.navyText.withValues(alpha: 0.55)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: ctrl,
                autofocus: true,
                maxLength: 80,
                decoration: InputDecoration(
                  hintText: 'at the coffee shop',
                  prefixIcon: const Text('🟢 ', style: TextStyle(fontSize: 18)),
                  prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 0),
                  counterText: '',
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  if ((profile.statusText ?? '').isNotEmpty)
                    TextButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        await ref.read(settingsProvider.notifier)
                            .updateProfile(profile.copyWith(statusText: ''));
                        if (!mounted) return;
                        context.showSuccess('Status cleared');
                      },
                      style: TextButton.styleFrom(foregroundColor: AppTheme.error),
                      child: const Text('Clear'),
                    ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () async {
                      final text = ctrl.text.trim();
                      Navigator.pop(ctx);
                      try {
                        await ref.read(settingsProvider.notifier)
                            .updateProfile(profile.copyWith(statusText: text));
                        if (!mounted) return;
                        context.showSuccess('Status updated');
                      } catch (_) {
                        if (!mounted) return;
                        context.showError('Could not save status');
                      }
                    },
                    style: FilledButton.styleFrom(backgroundColor: AppTheme.brightNavy),
                    child: const Text('Save'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showNotificationEditor() {
    final state = ref.read(settingsProvider);
    final userSettings = state.user;
    if (userSettings == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: SojornColors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: AppTheme.scaffoldBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Notification Gates', style: AppTheme.textTheme.headlineSmall),
            const SizedBox(height: 16),
            SwitchListTile(
              title: const Text('All Notifications'),
              value: userSettings.notificationsEnabled,
              onChanged: (v) => ref.read(settingsProvider.notifier).updateUser(
                  userSettings.copyWith(notificationsEnabled: v)),
            ),
            SwitchListTile(
              title: const Text('Pause Mode (Equanimity)'),
              subtitle: const Text('Mute all alerts for deep focus'),
              value: !userSettings.pushNotifications,
              onChanged: (v) => ref.read(settingsProvider.notifier).updateUser(
                  userSettings.copyWith(pushNotifications: !v)),
            ),
            if (userSettings.notificationsEnabled) ...[
              const Divider(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Notify me about',
                    style: AppTheme.textTheme.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              const SizedBox(height: 8),
              // Per-type toggles. These preferences are stored locally via
              // SharedPreferences until the backend gains per-type columns.
              _NotifToggle(prefKey: 'notif_likes',    label: 'Likes & reactions',       icon: Icons.favorite_border),
              _NotifToggle(prefKey: 'notif_comments', label: 'Comments & replies',       icon: Icons.chat_bubble_outline),
              _NotifToggle(prefKey: 'notif_follows',  label: 'New followers',             icon: Icons.person_add_outlined),
              _NotifToggle(prefKey: 'notif_groups',   label: 'Group & board activity',   icon: Icons.group_outlined),
              _NotifToggle(prefKey: 'notif_beacons',  label: 'Nearby Beacon alerts',     icon: Icons.sensors, defaultOn: true),
              _NotifToggle(prefKey: 'notif_messages', label: 'Direct messages',           icon: Icons.mail_outline, defaultOn: true),
              const Divider(height: 24),
              Align(
                alignment: Alignment.centerLeft,
                child: Text('Quiet hours',
                    style: AppTheme.textTheme.labelMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
              ),
              _NotifToggle(prefKey: 'notif_quiet',
                  label: 'Enable quiet hours (10 pm – 8 am)',
                  icon: Icons.bedtime_outlined),
            ],
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  void _showTtlEditor() {
    final state = ref.read(settingsProvider);
    final userSettings = state.user;
    if (userSettings == null) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: SojornColors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: AppTheme.scaffoldBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
             Text('Post Lifespan', style: AppTheme.textTheme.headlineSmall),
             const SizedBox(height: 8),
             Text('Impermanence is the nature of all things.', style: AppTheme.textTheme.labelSmall),
             const SizedBox(height: 24),
             Wrap(
               spacing: 8,
               children: [null, 12, 24, 72, 168].map((hours) => ChoiceChip(
                 label: Text(hours == null ? 'Eternal' : '$hours hrs'),
                 selected: userSettings.defaultPostTtl == hours,
                 onSelected: (s) => ref.read(settingsProvider.notifier).updateUser(userSettings.copyWith(defaultPostTtl: hours)),
               )).toList(),
             ),
             const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  void _showAestheticEditor() {
    final currentTheme = ref.read(app_theme.themeProvider);
    
    showModalBottomSheet(
      context: context,
      backgroundColor: SojornColors.transparent,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: AppTheme.scaffoldBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('Vibe & Aesthetic', style: AppTheme.headlineSmall),
            const SizedBox(height: 24),
            ListTile(
              title: const Text('Basic (Serene)'),
              subtitle: const Text('A calm, standard sanctuary experience'),
              leading: Radio<app_theme.ThemeMode>(
                value: app_theme.ThemeMode.basic,
                groupValue: currentTheme,
                onChanged: (v) {
                  ref.read(app_theme.themeProvider.notifier).setTheme(v!);
                  Navigator.pop(context);
                },
              ),
              onTap: () {
                ref.read(app_theme.themeProvider.notifier).setTheme(app_theme.ThemeMode.basic);
                Navigator.pop(context);
              },
            ),
            ListTile(
              title: const Text('Pop (Vibrant)'),
              subtitle: const Text('High energy, dynamic colors'),
              leading: Radio<app_theme.ThemeMode>(
                value: app_theme.ThemeMode.pop,
                groupValue: currentTheme,
                onChanged: (v) {
                  ref.read(app_theme.themeProvider.notifier).setTheme(v!);
                  Navigator.pop(context);
                },
              ),
              onTap: () {
                ref.read(app_theme.themeProvider.notifier).setTheme(app_theme.ThemeMode.pop);
                Navigator.pop(context);
              },
            ),
            const SizedBox(height: 48),
          ],
        ),
      ),
    );
  }

  Future<void> _pickMedia({required bool isBanner}) async {
    final XFile? file = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    if (!mounted) return;

    // Read bytes upfront — works on both web (blob URL) and mobile (file path).
    final bytes = await file.readAsBytes();

    final result = await Navigator.push<SojornMediaResult>(
      context,
      MaterialPageRoute(
        builder: (_) => sojornImageEditor(imageBytes: bytes, imageName: file.name),
      ),
    );

    if (result == null) return;

    setState(() => isBanner ? _isBannerUploading = true : _isAvatarUploading = true);

    try {
      final String url;
      if (result.bytes != null) {
        url = await _imageUploadService.uploadImageBytes(result.bytes!, fileName: result.name);
      } else {
        url = await _imageUploadService.uploadImage(File(result.filePath!));
      }
      final profile = ref.read(settingsProvider).profile;
      if (profile != null) {
        if (isBanner) {
          await ref.read(settingsProvider.notifier).updateProfile(profile.copyWith(coverUrl: url));
        } else {
          await ref.read(settingsProvider.notifier).updateProfile(profile.copyWith(avatarUrl: url));
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Upload failed: $e')));
      }
    } finally {
      if (mounted) {
        setState(() => isBanner ? _isBannerUploading = false : _isAvatarUploading = false);
      }
    }
  }

  // --- Account Lifecycle Dialogs ---

  void _showAccountRemovalSheet() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.remove_circle_outline, color: SojornColors.destructive, size: 24),
            const SizedBox(width: 8),
            const Text('Account Removal'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildRemovalOption(
              icon: Icons.pause_circle_outline,
              title: 'Deactivate',
              subtitle: 'Temporarily hide your profile. You can reactivate anytime.',
              color: SojornColors.nsfwWarningIcon,
              onTap: () {
                Navigator.of(ctx).pop();
                _showDeactivateDialog();
              },
            ),
            const SizedBox(height: 8),
            _buildRemovalOption(
              icon: Icons.delete_outline,
              title: 'Delete Account',
              subtitle: 'Permanently remove your account after a 30-day grace period.',
              color: SojornColors.destructive,
              onTap: () {
                Navigator.of(ctx).pop();
                _showDeleteDialog();
              },
            ),
            const SizedBox(height: 8),
            _buildRemovalOption(
              icon: Icons.warning_amber_rounded,
              title: 'Permanently Delete Now',
              subtitle: 'Immediately erase all data. This cannot be undone.',
              color: const Color(0xFFC62828),
              onTap: () {
                Navigator.of(ctx).pop();
                _showSuperDeleteDialog();
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
        ],
      ),
    );
  }

  Widget _buildRemovalOption({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: TextStyle(fontWeight: FontWeight.w700, color: color, fontSize: 14)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: TextStyle(fontSize: 12, color: AppTheme.navyText.withValues(alpha: 0.6))),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: color.withValues(alpha: 0.5), size: 20),
          ],
        ),
      ),
    );
  }

  void _showDeactivateDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.pause_circle_outline, color: SojornColors.nsfwWarningIcon, size: 24),
            const SizedBox(width: 8),
            const Text('Deactivate Account'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your account will be hidden and you will be logged out. '
              'All your data — posts, messages, connections — will be preserved indefinitely.\n\n'
              'You can reactivate at any time simply by logging back in.',
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: SojornColors.nsfwWarningIcon.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: SojornColors.nsfwWarningIcon.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.email_outlined, color: SojornColors.nsfwWarningIcon, size: 18),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'A confirmation email will be sent to your registered address.',
                      style: TextStyle(fontSize: 13),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(ctx);
              await _performDeactivation();
            },
            style: TextButton.styleFrom(foregroundColor: SojornColors.nsfwWarningIcon),
            child: const Text('Deactivate'),
          ),
        ],
      ),
    );
  }

  void _showDeleteDialog() {
    final confirmController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.delete_outline, color: SojornColors.destructive, size: 24),
              const SizedBox(width: 8),
              const Text('Delete Account'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your account will be deactivated immediately and permanently deleted after 14 days.\n\n'
                'During those 14 days, you can cancel the deletion by logging back in. '
                'After that, ALL data will be irreversibly destroyed.',
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: SojornColors.destructive.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: SojornColors.destructive.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Icon(Icons.email_outlined, color: SojornColors.destructive, size: 18),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'An email will be sent confirming the scheduled deletion and grace period.',
                        style: TextStyle(fontSize: 13),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('Type DELETE to confirm:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              TextField(
                controller: confirmController,
                onChanged: (_) => setDialogState(() {}),
                decoration: const InputDecoration(
                  hintText: 'DELETE',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: confirmController.text == 'DELETE'
                  ? () async {
                      Navigator.pop(ctx);
                      await _performDeletion();
                    }
                  : null,
              style: TextButton.styleFrom(foregroundColor: SojornColors.destructive),
              child: const Text('Delete My Account'),
            ),
          ],
        ),
      ),
    );
  }

  void _showSuperDeleteDialog() {
    final confirmController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: const Color(0xFFC62828), size: 24),
              const SizedBox(width: 8),
              Expanded(child: Text('Immediate Destroy', style: TextStyle(color: SojornColors.destructive))),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'THIS IS IRREVERSIBLE.',
                style: TextStyle(fontWeight: FontWeight.bold, color: const Color(0xFFC62828)),
              ),
              const SizedBox(height: 12),
              const Text(
                'A confirmation email will be sent to your registered address. '
                'When you click the link in that email, your account and ALL data '
                'will be permanently and immediately destroyed.',
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFB71C1C).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: const Color(0xFFC62828).withValues(alpha: 0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: const [
                    Text('What will be destroyed:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                    SizedBox(height: 4),
                    Text('Posts, messages, encryption keys, profile, followers, handle — everything. '
                        'There is NO recovery, NO backup, NO undo.',
                        style: TextStyle(fontSize: 13)),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text('Type DESTROY to continue:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
              const SizedBox(height: 8),
              TextField(
                controller: confirmController,
                onChanged: (_) => setDialogState(() {}),
                decoration: const InputDecoration(
                  hintText: 'DESTROY',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: confirmController.text == 'DESTROY'
                  ? () async {
                      Navigator.pop(ctx);
                      await _performSuperDelete();
                    }
                  : null,
              style: TextButton.styleFrom(
                foregroundColor: SojornColors.basicWhite,
                backgroundColor: confirmController.text == 'DESTROY' ? const Color(0xFFC62828) : AppTheme.textDisabled,
              ),
              child: const Text('Send Destroy Email'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _performDeactivation() async {
    try {
      final api = ref.read(apiServiceProvider);
      await api.callGoApi('/account/deactivate', method: 'POST');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Account deactivated. A confirmation email has been sent. Log back in anytime to reactivate.'),
          backgroundColor: SojornColors.nsfwWarningIcon,
        ),
      );
      await _signOut();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to deactivate: $e'), backgroundColor: SojornColors.destructive),
      );
    }
  }

  Future<void> _performDeletion() async {
    try {
      final api = ref.read(apiServiceProvider);
      final result = await api.callGoApi('/account', method: 'DELETE');
      if (!mounted) return;
      final deletionDate = result['deletion_date'] ?? '14 days';
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.email, color: SojornColors.destructive, size: 24),
              const SizedBox(width: 8),
              const Text('Deletion Scheduled'),
            ],
          ),
          content: Text(
            'Your account is scheduled for permanent deletion on $deletionDate.\n\n'
            'A confirmation email has been sent to your registered address with all the details.\n\n'
            'To cancel, simply log back in before that date.',
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.pop(ctx);
                _signOut();
              },
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to schedule deletion: $e'), backgroundColor: SojornColors.destructive),
      );
    }
  }

  Future<void> _performSuperDelete() async {
    try {
      final api = ref.read(apiServiceProvider);
      await api.callGoApi('/account/destroy', method: 'POST');
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          title: Row(
            children: [
              Icon(Icons.mark_email_read, color: const Color(0xFFC62828), size: 24),
              const SizedBox(width: 8),
              const Expanded(child: Text('Confirmation Email Sent')),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'A confirmation email has been sent to your registered address.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              const Text(
                'You MUST click the link in that email to complete the destruction. '
                'Your account will be destroyed the instant you click that link.',
              ),
              const SizedBox(height: 12),
              Text(
                'If you did not mean to do this, simply ignore the email \u2014 your account will not be affected. '
                'The link expires in 1 hour.',
                style: TextStyle(color: AppTheme.textDisabled),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to initiate destroy: $e'), backgroundColor: SojornColors.destructive),
      );
    }
  }

  Future<void> _signOut() async {
    final authService = ref.read(authServiceProvider);
    await NotificationService.instance.removeToken();
    await authService.signOut();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }
}

/// Self-contained per-notification-type toggle backed by SharedPreferences.
/// Uses a FutureBuilder to load the initial value and saves changes instantly.
class _NotifToggle extends StatefulWidget {
  final String prefKey;
  final String label;
  final IconData icon;
  final bool defaultOn;

  const _NotifToggle({
    required this.prefKey,
    required this.label,
    required this.icon,
    this.defaultOn = false,
  });

  @override
  State<_NotifToggle> createState() => _NotifToggleState();
}

class _NotifToggleState extends State<_NotifToggle> {
  bool? _value;

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((prefs) {
      if (mounted) {
        setState(() {
          _value = prefs.getBool(widget.prefKey) ?? widget.defaultOn;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final value = _value;
    if (value == null) return const SizedBox(height: 48);
    return SwitchListTile(
      secondary: Icon(widget.icon, size: 20, color: AppTheme.egyptianBlue),
      title: Text(widget.label, style: const TextStyle(fontSize: 14)),
      value: value,
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4),
      onChanged: (v) async {
        setState(() => _value = v);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setBool(widget.prefKey, v);
      },
    );
  }
}

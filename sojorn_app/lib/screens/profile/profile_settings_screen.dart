import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
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
import '../../widgets/app_scaffold.dart';
import '../../widgets/media/signed_media_image.dart';
import '../../widgets/sojorn_input.dart';
import '../../services/api_service.dart';
import '../../widgets/sojorn_text_area.dart';
import 'follow_requests_screen.dart';
import 'blocked_users_screen.dart';
import 'category_settings_screen.dart';
import '../compose/image_editor_screen.dart';
import '../../models/sojorn_media_result.dart';
import '../security/encryption_hub_screen.dart';
import '../../widgets/neighborhood/neighborhood_picker_sheet.dart';

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
    
    if (state.isLoading && profile == null) {
      return const AppScaffold(
        title: 'Settings',
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (profile == null) {
      return const AppScaffold(
        title: 'Settings',
        body: Center(child: Text('Failed to load profile')),
      );
    }

    return AppScaffold(
      title: 'Sanctuary Settings',
      body: SingleChildScrollView(
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
                     title: 'Account Sovereignty',
                     subtitle: 'Your data, your sanctuary',
                     children: [
                       _buildEditTile(
                         icon: Icons.person_outline,
                         title: 'Identity',
                         onTap: () => _showIdentityEditor(profile),
                       ),
                       _buildEditTile(
                         icon: Icons.lock,
                         title: 'Encryption & Backup',
                         onTap: () => Navigator.of(context).push(
                           MaterialPageRoute(builder: (_) => const EncryptionHubScreen()),
                         ),
                       ),
                       _buildEditTile(
                         icon: Icons.shield_outlined,
                         title: 'Discovery Cohorts',
                         onTap: () => Navigator.of(context).push(
                           MaterialPageRoute(builder: (_) => const CategoryDiscoveryScreen()),
                         ),
                       ),
                       _buildEditTile(
                         icon: Icons.pause_circle_outline,
                         title: 'Deactivate Account',
                         color: SojornColors.nsfwWarningIcon,
                         onTap: () => _showDeactivateDialog(),
                       ),
                       _buildEditTile(
                         icon: Icons.delete_outline,
                         title: 'Delete Account',
                         color: SojornColors.destructive,
                         onTap: () => _showDeleteDialog(),
                       ),
                       _buildEditTile(
                         icon: Icons.warning_amber_rounded,
                         title: 'Immediate Destroy',
                         color: const Color(0xFFC62828),
                         onTap: () => _showSuperDeleteDialog(),
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
                         onTap: () => Navigator.of(context).push(
                           MaterialPageRoute(builder: (_) => const FollowRequestsScreen()),
                         ),
                       ),
                       _buildEditTile(
                         icon: Icons.block_flipped,
                         title: 'Blocked',
                         onTap: () => Navigator.of(context).push(
                           MaterialPageRoute(builder: (_) => const BlockedUsersScreen()),
                         ),
                       ),
                       _buildEditTile(
                         icon: Icons.visibility_outlined,
                         title: 'Privacy Gates',
                         onTap: () => _showPrivacyEditor(),
                       ),
                       _buildEditTile(
                         icon: Icons.dashboard_outlined,
                         title: 'Privacy Dashboard',
                         onTap: () => Navigator.of(context).push(
                           MaterialPageRoute(builder: (_) => const PrivacyDashboardScreen()),
                         ),
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
      ),
    );
  }

  Widget _buildProfileHeader(Profile profile) {
    return Stack(
      children: [
        // Banner
        GestureDetector(
          onTap: () => _pickMedia(isBanner: true),
          child: Container(
            height: 180,
            width: double.infinity,
            decoration: BoxDecoration(
              color: AppTheme.egyptianBlue.withValues(alpha: 0.1),
            ),
            child: _isBannerUploading
              ? const Center(child: CircularProgressIndicator())
              : profile.coverUrl != null
                ? SignedMediaImage(url: profile.coverUrl!, fit: BoxFit.cover)
                : Center(child: Icon(Icons.add_photo_alternate_outlined, color: AppTheme.egyptianBlue.withValues(alpha: 0.5), size: 40)),
          ),
        ),
        // Glass Overlay for Banner Action
        Positioned(
          bottom: 12,
          right: 12,
          child: _buildGlassButton(
            onTap: () => _pickMedia(isBanner: true),
            icon: Icons.camera_alt_outlined,
          ),
        ),
        // Avatar
        Positioned(
          top: 130,
          left: 24,
          child: GestureDetector(
            onTap: () => _pickMedia(isBanner: false),
            child: Stack(
              children: [
                CircleAvatar(
                  radius: 42,
                  backgroundColor: AppTheme.scaffoldBg,
                  child: CircleAvatar(
                    radius: 38,
                    backgroundColor: AppTheme.queenPink,
                    child: _isAvatarUploading
                      ? const CircularProgressIndicator()
                      : profile.avatarUrl != null
                        ? ClipOval(
                            child: SignedMediaImage(url: profile.avatarUrl!, width: 76, height: 76, fit: BoxFit.cover),
                          )
                        : Text(profile.displayName?[0].toUpperCase() ?? '?', style: AppTheme.headlineSmall),
                  ),
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: AppTheme.brightNavy,
                      shape: BoxShape.circle,
                      border: Border.all(color: AppTheme.scaffoldBg, width: 2),
                    ),
                    child: const Icon(Icons.add_a_photo, size: 14, color: SojornColors.basicWhite),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHarmonyInsight(SettingsState state) {
    final trust = state.trust;
    if (trust == null) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(AppTheme.spacingMd),
      decoration: BoxDecoration(
        color: AppTheme.royalPurple.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.royalPurple.withValues(alpha: 0.2)),
      ),
      child: Row(
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
                Text('Harmony State: ${trust.tier.displayName}', style: AppTheme.textTheme.labelMedium),
                const SizedBox(height: 2),
                Text(
                  'Your current reach multiplier is based on your contribution to the community.',
                  style: AppTheme.textTheme.bodySmall?.copyWith(color: AppTheme.navyText.withValues(alpha: 0.6)),
                ),
              ],
            ),
          ),
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
            color: SojornColors.basicWhite.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: AppTheme.egyptianBlue.withValues(alpha: 0.1)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: children),
        ),
      ],
    );
  }

  Widget _buildEditTile({required IconData icon, required String title, required VoidCallback onTap, Color? color}) {
    return ListTile(
      onTap: onTap,
      leading: Icon(icon, color: color ?? AppTheme.navyBlue, size: 22),
      title: Text(title, style: AppTheme.textTheme.bodyLarge),
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
        label: const Text('Return to Silence (Logout)'),
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
            'You can only change your neighborhood once per month.\n\nYour next change is available on ${_formatDateShort(nextChange)}.',
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
                  style: AppTheme.textTheme.labelSmall?.copyWith(color: SojornColors.textDisabled),
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
              onChanged: (v) => ref.read(settingsProvider.notifier).updateUser(userSettings.copyWith(notificationsEnabled: v)),
            ),
            SwitchListTile(
              title: const Text('Pause Mode (Equanimity)'),
              subtitle: const Text('Mute all alerts for deep focus'),
              value: !userSettings.pushNotifications,
              onChanged: (v) => ref.read(settingsProvider.notifier).updateUser(userSettings.copyWith(pushNotifications: !v)),
            ),
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
    final result = await Navigator.push<SojornMediaResult>(
      context,
      MaterialPageRoute(
        builder: (_) => sojornImageEditor(imagePath: file.path, imageName: file.name),
      ),
    );

    if (result == null) return;

    setState(() => isBanner ? _isBannerUploading = true : _isAvatarUploading = true);

    try {
      final url = await _imageUploadService.uploadImage(File(result.filePath!));
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
            children: const [
              Text(
                'A confirmation email has been sent to your registered address.',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              SizedBox(height: 12),
              Text(
                'You MUST click the link in that email to complete the destruction. '
                'Your account will be destroyed the instant you click that link.',
              ),
              SizedBox(height: 12),
              Text(
                'If you did not mean to do this, simply ignore the email — your account will not be affected. '
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

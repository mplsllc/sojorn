// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/post.dart';
import '../../models/beacon.dart';
import '../../providers/api_provider.dart';
import '../../theme/tokens.dart';
import '../../theme/app_theme.dart';
import '../../utils/snackbar_ext.dart';

class BeaconDetailScreen extends ConsumerStatefulWidget {
  final Post beaconPost;

  const BeaconDetailScreen({super.key, required this.beaconPost});

  @override
  ConsumerState<BeaconDetailScreen> createState() => _BeaconDetailScreenState();
}

class _BeaconDetailScreenState extends ConsumerState<BeaconDetailScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
  bool _isVouching = false;
  bool _isReporting = false;
  bool _isResolving = false;
  // Tracks the current user's vote locally so the UI updates immediately.
  // Initialised from the server-returned my_vote field; updated optimistically.
  String? _userVote; // "vouch", "report", or null

  @override
  void initState() {
    super.initState();
    _userVote = widget.beaconPost.toBeacon().userVote;

    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    final beacon = widget.beaconPost.toBeacon();
    if (beacon.isRecent) {
      _pulseAnimation = Tween<double>(begin: 0.9, end: 1.05).animate(
        CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
      );
      _pulseController.repeat(reverse: true);
    } else {
      _pulseAnimation = const AlwaysStoppedAnimation(1.0);
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  Beacon get _beacon => widget.beaconPost.toBeacon();
  Post get _post => widget.beaconPost;

  /// Beacon is expired if the server set an expires_at and it has passed,
  /// or as a fallback, unverified reports expire 4 hours after creation.
  bool get _isExpired {
    final ea = _post.expiresAt;
    if (ea != null) return DateTime.now().isAfter(ea);
    return _beacon.verificationCount < 3 &&
        DateTime.now().difference(_beacon.createdAt).inHours >= 4;
  }

  @override
  Widget build(BuildContext context) {
    final severityColor = _beacon.pinColor;

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      body: CustomScrollView(
        slivers: [
          _buildHeader(severityColor),
          SliverToBoxAdapter(
            child: Container(
              decoration: BoxDecoration(
                color: AppTheme.cardSurface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildIncidentInfo(severityColor),
                  _buildMetaRow(),
                  _buildVerificationSection(severityColor),
                  const SizedBox(height: 12),
                  _buildActionButtons(severityColor),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(Color severityColor) {
    final hasImage = _post.imageUrl != null && _post.imageUrl!.isNotEmpty;

    return SliverAppBar(
      expandedHeight: hasImage ? 280 : 140,
      pinned: true,
      backgroundColor: AppTheme.scaffoldBg,
      leading: Container(
        margin: const EdgeInsets.all(8),
        decoration: BoxDecoration(color: const Color(0x61000000), borderRadius: BorderRadius.circular(12)),
        child: IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.arrow_back, color: SojornColors.basicWhite),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Stack(
          fit: StackFit.expand,
          children: [
            if (hasImage)
              Image.network(_post.imageUrl!, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildFallbackHeader(severityColor))
            else
              _buildFallbackHeader(severityColor),

            // Dark gradient overlay
            Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [const Color(0x99000000), SojornColors.transparent, const Color(0x80000000)],
                ),
              ),
            ),

            // Severity badge — size and style scale with urgency
            Positioned(
              top: 60, right: 16,
              child: AnimatedBuilder(
                animation: _pulseAnimation,
                builder: (context, child) {
                  final isCritical = _beacon.severity == BeaconSeverity.critical;
                  final isHigh = _beacon.severity == BeaconSeverity.high;
                  final isLow = _beacon.severity == BeaconSeverity.low;
                  return Transform.scale(
                    scale: _pulseAnimation.value,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isCritical || isHigh ? 12 : 10,
                        vertical: isCritical || isHigh ? 7 : 5,
                      ),
                      decoration: BoxDecoration(
                        color: isLow
                            ? severityColor.withValues(alpha: 0.15)
                            : severityColor.withValues(alpha: 0.9),
                        borderRadius: BorderRadius.circular(isCritical ? 8 : 16),
                        border: isLow ? Border.all(color: severityColor.withValues(alpha: 0.5)) : null,
                        boxShadow: isLow ? null : [
                          BoxShadow(
                            color: severityColor.withValues(alpha: isCritical ? 0.6 : 0.3),
                            blurRadius: isCritical ? 14 : 8,
                            spreadRadius: isCritical ? 3 : 1,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_beacon.severity.icon,
                            color: isLow ? severityColor : SojornColors.basicWhite,
                            size: isCritical ? 16 : 13),
                          const SizedBox(width: 4),
                          Text(
                            isCritical ? '⚠ ${_beacon.severity.label.toUpperCase()}' : _beacon.severity.label,
                            style: TextStyle(
                              color: isLow ? severityColor : SojornColors.basicWhite,
                              fontWeight: FontWeight.bold,
                              fontSize: isCritical ? 12 : 10,
                              letterSpacing: isCritical ? 0.5 : 0,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // LIVE badge
            if (_beacon.isRecent)
              Positioned(
                top: 60, left: 60,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: SojornColors.destructive, borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text('LIVE', style: TextStyle(color: SojornColors.basicWhite, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallbackHeader(Color severityColor) {
    return Container(
      color: AppTheme.scaffoldBg,
      child: Center(
        child: Container(
          width: 80, height: 80,
          decoration: BoxDecoration(
            color: severityColor.withValues(alpha: 0.2),
            shape: BoxShape.circle,
          ),
          child: Icon(_beacon.beaconType.icon, color: severityColor, size: 40),
        ),
      ),
    );
  }

  Widget _buildIncidentInfo(Color severityColor) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: severityColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(_beacon.beaconType.icon, color: severityColor, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_beacon.beaconType.displayName,
                      style: TextStyle(color: AppTheme.navyBlue, fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 2),
                    Text('${_beacon.getFormattedDistance()} away',
                      style: TextStyle(color: SojornColors.textDisabled, fontSize: 13)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(_post.body,
            style: TextStyle(color: SojornColors.postContent, fontSize: 15, height: 1.5)),
        ],
      ),
    );
  }

  Widget _buildMetaRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppTheme.scaffoldBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.08)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _metaItem(Icons.schedule, _beacon.getTimeAgo()),
            _metaItem(Icons.location_on, _beacon.getFormattedDistance()),
            _metaItem(Icons.visibility, '${_beacon.verificationCount} verified'),
            _metaItem(Icons.radar, '${_beacon.radius}m radius'),
          ],
        ),
      ),
    );
  }

  Widget _metaItem(IconData icon, String label) {
    return Column(
      children: [
        Icon(icon, size: 16, color: SojornColors.textDisabled),
        const SizedBox(height: 4),
        Text(label, style: TextStyle(color: SojornColors.textDisabled, fontSize: 10)),
      ],
    );
  }

  Widget _buildVerificationSection(Color severityColor) {
    final verCount = _beacon.verificationCount;
    final isVerified = verCount >= 3;

    // Determine state: verified → awaiting → expired
    final Color statusColor;
    final String statusText;
    final IconData statusIcon;
    final String subText;
    final Color borderColor;

    if (isVerified) {
      statusColor = const Color(0xFF4CAF50);
      statusText = 'Verified by community';
      statusIcon = Icons.verified;
      subText = '$verCount / 3 neighbors confirmed this report';
      borderColor = const Color(0xFF4CAF50).withValues(alpha: 0.3);
    } else if (_isExpired) {
      statusColor = SojornColors.textDisabled;
      statusText = 'Verification expired';
      statusIcon = Icons.timer_off_outlined;
      subText = 'Only $verCount / 3 verifications received before the 4-hour window closed';
      borderColor = SojornColors.textDisabled.withValues(alpha: 0.2);
    } else {
      statusColor = SojornColors.nsfwWarningIcon;
      statusText = 'Awaiting verification';
      statusIcon = Icons.pending;
      subText = '$verCount / 3 neighbors confirmed this report';
      borderColor = AppTheme.navyBlue.withValues(alpha: 0.08);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Community Verification',
            style: TextStyle(color: AppTheme.navyBlue.withValues(alpha: 0.6), fontSize: 13, fontWeight: FontWeight.w600)),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: AppTheme.scaffoldBg,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: borderColor),
            ),
            child: Row(
              children: [
                Icon(statusIcon, color: statusColor, size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(statusText,
                        style: TextStyle(color: statusColor, fontSize: 14, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(subText,
                        style: TextStyle(color: SojornColors.textDisabled, fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: (verCount / 3).clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: AppTheme.navyBlue.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation<Color>(statusColor),
            ),
          ),
          // Only show countdown when still active (not expired, not verified)
          if (!isVerified && !_isExpired) ...[
            const SizedBox(height: 8),
            _buildExpiryCountdown(),
          ],
        ],
      ),
    );
  }

  Widget _buildExpiryCountdown() {
    final expiry = _beacon.createdAt.add(const Duration(hours: 4));
    final now = DateTime.now();
    final remaining = expiry.difference(now);

    if (remaining.isNegative) return const SizedBox.shrink();

    final hours = remaining.inHours;
    final minutes = remaining.inMinutes % 60;
    final timeStr = hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';

    return Row(
      children: [
        Icon(Icons.timer_outlined, size: 12, color: SojornColors.nsfwWarningIcon),
        const SizedBox(width: 4),
        Expanded(
          child: Text('Expires in $timeStr if not verified by the community',
            style: TextStyle(color: SojornColors.nsfwWarningIcon, fontSize: 11)),
        ),
      ],
    );
  }

  /// Compact urgency row shown directly above the vouch button.
  Widget _buildVouchUrgencyBanner() {
    final isVerified = _beacon.verificationCount >= 3;
    if (isVerified || _isExpired) return const SizedBox.shrink();

    final expiry = _beacon.createdAt.add(const Duration(hours: 4));
    final remaining = expiry.difference(DateTime.now());
    if (remaining.isNegative) return const SizedBox.shrink();

    final hours = remaining.inHours;
    final minutes = remaining.inMinutes % 60;
    final timeStr = hours > 0 ? '${hours}h ${minutes}m' : '${minutes}m';

    // Pick urgency color: red if under 30 min, orange otherwise
    final isUrgent = remaining.inMinutes < 30;
    final urgencyColor = isUrgent ? SojornColors.destructive : SojornColors.nsfwWarningIcon;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: urgencyColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: urgencyColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Icon(Icons.timer_outlined, size: 14, color: urgencyColor),
          const SizedBox(width: 7),
          Expanded(
            child: Text(
              'Needs verification in $timeStr or it expires',
              style: TextStyle(color: urgencyColor, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(Color severityColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: _isExpired
          ? Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: SojornColors.textDisabled.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: SojornColors.textDisabled.withValues(alpha: 0.2)),
              ),
              child: Column(
                children: [
                  Icon(Icons.timer_off_outlined, size: 22, color: SojornColors.textDisabled),
                  const SizedBox(height: 6),
                  Text('This report has expired',
                    style: TextStyle(color: SojornColors.textDisabled, fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text('Not enough community verifications within 4 hours',
                    style: TextStyle(color: SojornColors.textDisabled, fontSize: 11)),
                ],
              ),
            )
          : Column(
              children: [
                // Urgency CTA — show expiry time right above the verify button
                _buildVouchUrgencyBanner(),
                const SizedBox(height: 8),
                // "I see this too" button — primary confirm action
                SizedBox(
                  width: double.infinity,
                  height: 50,
                  child: ElevatedButton.icon(
                    onPressed: _isVouching || _isReporting
                        ? null
                        : (_userVote == 'vouch' ? _unvoteBeacon : _vouchBeacon),
                    icon: _isVouching
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: SojornColors.basicWhite))
                        : Icon(
                            _userVote == 'vouch' ? Icons.check_circle : Icons.visibility,
                            size: 20,
                          ),
                    label: Text(
                      _isVouching
                          ? 'Confirming...'
                          : (_userVote == 'vouch' ? 'You confirmed this — Undo' : 'I see this too'),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _userVote == 'vouch'
                          ? const Color(0xFF2E7D32)  // darker green when voted
                          : const Color(0xFF388E3C),
                      foregroundColor: SojornColors.basicWhite,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      disabledBackgroundColor: const Color(0xFF4CAF50).withValues(alpha: 0.3),
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                // False alarm / report button — secondary action
                SizedBox(
                  width: double.infinity,
                  height: 44,
                  child: OutlinedButton.icon(
                    onPressed: _isReporting || _isVouching
                        ? null
                        : (_userVote == 'report' ? _unvoteBeacon : _reportBeacon),
                    icon: _isReporting
                        ? SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: SojornColors.destructive))
                        : Icon(
                            _userVote == 'report' ? Icons.flag : Icons.flag_outlined,
                            size: 18,
                            color: _userVote == 'report'
                                ? SojornColors.destructive
                                : SojornColors.destructive.withValues(alpha: 0.7),
                          ),
                    label: Text(
                      _isReporting
                          ? 'Reporting...'
                          : (_userVote == 'report' ? 'You reported this — Undo' : 'False alarm / Report'),
                      style: TextStyle(
                        color: _userVote == 'report'
                            ? SojornColors.destructive
                            : SojornColors.destructive.withValues(alpha: 0.7),
                        fontSize: 13,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: _userVote == 'report'
                            ? SojornColors.destructive
                            : SojornColors.destructive.withValues(alpha: 0.3),
                      ),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                // Resolved — tertiary community action
                SizedBox(
                  width: double.infinity,
                  height: 40,
                  child: TextButton.icon(
                    onPressed: _isResolving ? null : _resolveBeacon,
                    icon: _isResolving
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.check_circle_outline, size: 16),
                    label: Text(_isResolving ? 'Marking resolved...' : 'Situation resolved',
                      style: const TextStyle(fontSize: 13)),
                  ),
                ),
              ],
            ),
    );
  }

  Future<void> _vouchBeacon() async {
    final apiService = ref.read(apiServiceProvider);
    setState(() => _isVouching = true);
    try {
      await apiService.vouchBeacon(_post.id);
      if (mounted) {
        setState(() => _userVote = 'vouch');
        context.showSuccess('Thanks for confirming this report!');
      }
    } catch (e) {
      if (mounted) context.showError('Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _isVouching = false);
    }
  }

  Future<void> _reportBeacon() async {
    final apiService = ref.read(apiServiceProvider);
    setState(() => _isReporting = true);
    try {
      await apiService.reportBeacon(_post.id);
      if (mounted) {
        setState(() => _userVote = 'report');
        context.showInfo('Report received. Thanks for keeping the community safe.');
      }
    } catch (e) {
      if (mounted) context.showError('Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _isReporting = false);
    }
  }

  Future<void> _unvoteBeacon() async {
    final apiService = ref.read(apiServiceProvider);
    final previous = _userVote;
    setState(() {
      _isVouching = previous == 'vouch';
      _isReporting = previous == 'report';
    });
    try {
      await apiService.removeBeaconVote(_post.id);
      if (mounted) {
        setState(() => _userVote = null);
        context.showInfo('Vote removed.');
      }
    } catch (e) {
      if (mounted) context.showError('Something went wrong: $e');
    } finally {
      if (mounted) setState(() { _isVouching = false; _isReporting = false; });
    }
  }

  Future<void> _resolveBeacon() async {
    final apiService = ref.read(apiServiceProvider);
    setState(() => _isResolving = true);
    try {
      await apiService.resolveBeacon(_post.id, 'resolved');
      if (mounted) {
        context.showSuccess('Beacon marked as resolved. Thanks for the update!');
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) context.showError('Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _isResolving = false);
    }
  }
}

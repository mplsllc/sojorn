import 'dart:ui';
import 'package:flutter/material.dart';
import '../../models/post.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../services/api_service.dart';

class SanctuarySheet extends StatefulWidget {
  final Post post;

  const SanctuarySheet({super.key, required this.post});

  static Future<void> show(BuildContext context, Post post) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: SojornColors.transparent,
      isScrollControlled: true,
      builder: (_) => SanctuarySheet(post: post),
    );
  }

  /// Lightweight popup menu — no full-screen takeover.
  /// Reports are submitted immediately; block shows a compact confirmation.
  static Future<void> showQuick(
    BuildContext context,
    Post post,
    Offset tapPosition,
  ) async {
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        tapPosition.dx,
        tapPosition.dy,
        tapPosition.dx + 1,
        tapPosition.dy + 1,
      ),
      items: const [
        PopupMenuItem(
          value: 'harassment',
          child: Row(children: [
            Icon(Icons.flag_outlined, size: 18),
            SizedBox(width: 10),
            Text('Flag: Harassment'),
          ]),
        ),
        PopupMenuItem(
          value: 'scam',
          child: Row(children: [
            Icon(Icons.flag_outlined, size: 18),
            SizedBox(width: 10),
            Text('Flag: Scam / Fraud'),
          ]),
        ),
        PopupMenuItem(
          value: 'misinformation',
          child: Row(children: [
            Icon(Icons.flag_outlined, size: 18),
            SizedBox(width: 10),
            Text('Flag: Misinformation'),
          ]),
        ),
        PopupMenuDivider(),
        PopupMenuItem(
          value: 'block',
          child: Row(children: [
            Icon(Icons.block, size: 18, color: SojornColors.destructive),
            SizedBox(width: 10),
            Text('Block User',
                style: TextStyle(color: SojornColors.destructive)),
          ]),
        ),
      ],
    );

    if (value == null || !context.mounted) return;

    if (value == 'block') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Block User?'),
          content: Text(
            'This will structurally separate you and '
            '@${post.author?.handle ?? 'this user'}.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: SojornColors.destructive),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Block',
                  style: TextStyle(color: SojornColors.basicWhite)),
            ),
          ],
        ),
      );
      if (confirmed != true || !context.mounted) return;
      try {
        await ApiService.instance
            .callGoApi('/users/${post.authorId}/block', method: 'POST');
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User blocked.')),
          );
        }
      } catch (_) {}
    } else {
      try {
        await ApiService.instance.callGoApi(
          '/users/report',
          method: 'POST',
          body: {
            'target_user_id': post.authorId,
            'post_id': post.id,
            'violation_type': value,
            'description': '',
          },
        );
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Report submitted. Thank you.')),
          );
        }
      } catch (_) {}
    }
  }

  @override
  State<SanctuarySheet> createState() => _SanctuarySheetState();
}

class _SanctuarySheetState extends State<SanctuarySheet> {
  int _step = 0; // 0: Options, 1: Report Type, 2: Report Description, 3: Block Confirmation
  String? _violationType;
  final TextEditingController _descriptionController = TextEditingController();
  bool _isProcessing = false;

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.scaffoldBg,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          border: Border.all(
            color: AppTheme.egyptianBlue.withValues(alpha: 0.1),
            width: 1.5,
          ),
        ),
        padding: EdgeInsets.fromLTRB(24, 12, 24, MediaQuery.of(context).viewInsets.bottom + 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 5,
              decoration: BoxDecoration(
                color: AppTheme.egyptianBlue.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            const SizedBox(height: 24),
            _buildContent(),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_isProcessing) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: CircularProgressIndicator(),
      );
    }

    switch (_step) {
      case 0:
        return _buildOptions();
      case 1:
        return _buildReportTypes();
      case 2:
        return _buildReportDescription();
      case 3:
        return _buildBlockConfirmation();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildOptions() {
    return Column(
      children: [
        Text(
          "The Sanctuary",
          style: AppTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          "Protect the harmony of your Circle.",
          style: AppTheme.labelSmall.copyWith(
            color: AppTheme.navyText.withValues(alpha: 0.6),
          ),
        ),
        const SizedBox(height: 32),
        _buildActionTile(
          icon: Icons.flag_outlined,
          title: "Report Violation",
          subtitle: "Harassment, Scam, or Misinformation detected",
          onTap: () => setState(() => _step = 1),
        ),
        const SizedBox(height: 16),
        _buildActionTile(
          icon: Icons.block_flipped,
          title: "Exclude User",
          subtitle: "Stop all interactions structurally",
          color: SojornColors.destructive.withValues(alpha: 0.8),
          onTap: () => setState(() => _step = 3),
        ),
      ],
    );
  }

  Widget _buildReportTypes() {
    final types = [
      {'id': 'harassment', 'label': 'Harassment', 'desc': 'Hostility or aggression'},
      {'id': 'scam', 'label': 'Scam / Fraud', 'desc': 'Fraudulent or manipulative content'},
      {'id': 'misinformation', 'label': 'Misinformation', 'desc': 'False or harmful ignorance'},
    ];

    return Column(
      children: [
        Text(
          "Natures of Violation",
          style: AppTheme.headlineSmall.copyWith(fontSize: 20),
        ),
        const SizedBox(height: 24),
        ...types.map((t) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: _buildActionTile(
            title: t['label']!,
            subtitle: t['desc']!,
            onTap: () {
              setState(() {
                _violationType = t['id'];
                _step = 2;
              });
            },
          ),
        )),
        TextButton(
          onPressed: () => setState(() => _step = 0),
          child: Text("Back", style: TextStyle(color: AppTheme.egyptianBlue)),
        ),
      ],
    );
  }

  Widget _buildReportDescription() {
    return Column(
      children: [
        Text(
          "Detail the Disturbance",
          style: AppTheme.headlineSmall.copyWith(fontSize: 20),
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _descriptionController,
          maxLines: 4,
          style: TextStyle(color: AppTheme.navyText),
          decoration: InputDecoration(
            hintText: "Briefly describe the violation...",
            hintStyle: TextStyle(color: AppTheme.navyText.withValues(alpha: 0.4)),
            filled: true,
            fillColor: AppTheme.egyptianBlue.withValues(alpha: 0.05),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(15),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.brightNavy,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
            onPressed: _submitReport,
            child: const Text("Submit Report", style: TextStyle(color: SojornColors.basicWhite)),
          ),
        ),
        TextButton(
          onPressed: () => setState(() => _step = 1),
          child: Text("Back", style: TextStyle(color: AppTheme.egyptianBlue)),
        ),
      ],
    );
  }

  Widget _buildBlockConfirmation() {
    return Column(
      children: [
        const Icon(Icons.warning_amber_rounded, color: SojornColors.destructive, size: 64),
        const SizedBox(height: 16),
        Text(
          "Exclude from Circle?",
          style: AppTheme.headlineSmall.copyWith(fontSize: 22, color: AppTheme.error),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Text(
            "This will structurally separate you and @${widget.post.author?.handle ?? 'this user'}. You will both be invisible to each other across Sojorn.",
            textAlign: TextAlign.center,
            style: AppTheme.bodyMedium.copyWith(color: AppTheme.navyText.withValues(alpha: 0.7)),
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: SojornColors.destructive,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
            ),
            onPressed: _confirmBlock,
            child: const Text("Yes, Exclude structurally", style: TextStyle(color: SojornColors.basicWhite)),
          ),
        ),
        const SizedBox(height: 8),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text("Cancel", style: TextStyle(color: AppTheme.egyptianBlue)),
        ),
      ],
    );
  }

  Widget _buildActionTile({
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    IconData? icon,
    Color? color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(15),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: (color ?? AppTheme.navyText).withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(15),
          border: Border.all(color: (color ?? AppTheme.navyText).withValues(alpha: 0.1)),
        ),
        child: Row(
          children: [
            if (icon != null) ...[
              Icon(icon, color: color ?? AppTheme.navyText.withValues(alpha: 0.7), size: 28),
              const SizedBox(width: 16),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: AppTheme.labelLarge.copyWith(color: color ?? AppTheme.navyText)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: AppTheme.labelSmall.copyWith(color: (color ?? AppTheme.navyText).withValues(alpha: 0.6))),
                ],
              ),
            ),
            Icon(Icons.chevron_right, color: AppTheme.egyptianBlue.withValues(alpha: 0.3)),
          ],
        ),
      ),
    );
  }

  Future<void> _submitReport() async {
    setState(() => _isProcessing = true);
    try {
      await ApiService.instance.callGoApi(
        '/users/report',
        method: 'POST',
        body: {
          'target_user_id': widget.post.authorId,
          'post_id': widget.post.id,
          'violation_type': _violationType,
          'description': _descriptionController.text,
        },
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Report submitted. Thank you for maintaining harmony.")),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _confirmBlock() async {
    setState(() => _isProcessing = true);
    try {
      await ApiService.instance.callGoApi(
        '/users/${widget.post.authorId}/block',
        method: 'POST',
      );
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Structural exclusion complete.")),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _isProcessing = false);
    }
  }
}

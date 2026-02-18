import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_animate/flutter_animate.dart';
import '../../theme/app_theme.dart';

enum ReactionsDisplayMode {
  /// Comprehensive list of all reactions (Thread view)
  full,
  /// Single prioritized reaction chip (Feed view)
  compact,
}

/// Single Authority for reaction presentation and interaction.
///
/// Handles:
/// - [ReactionsDisplayMode.full]: Multiple chips with optional 'Add' button.
/// - [ReactionsDisplayMode.compact]: Single prioritized chip.
class ReactionsDisplay extends StatelessWidget {
  final Map<String, int> reactionCounts;
  final Set<String> myReactions;
  final Map<String, List<String>>? reactionUsers;
  final Function(String)? onToggleReaction;
  final VoidCallback? onAddReaction;
  final ReactionsDisplayMode mode;
  final EdgeInsets? padding;

  const ReactionsDisplay({
    super.key,
    required this.reactionCounts,
    required this.myReactions,
    this.reactionUsers,
    this.onToggleReaction,
    this.onAddReaction,
    this.mode = ReactionsDisplayMode.full,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    if (reactionCounts.isEmpty && onAddReaction == null) {
      return const SizedBox.shrink();
    }

    if (mode == ReactionsDisplayMode.compact) {
      return _buildCompactView();
    }

    return _buildFullView();
  }

  Widget _buildCompactView() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (reactionCounts.isNotEmpty) _buildTopReactionChip(),
        if (onAddReaction != null) ...[
          if (reactionCounts.isNotEmpty) const SizedBox(width: 8),
          _ReactionAddButton(onTap: onAddReaction!),
        ],
      ],
    );
  }

  Widget _buildTopReactionChip() {
    // Priority: User's reaction > Top reaction
    String? displayEmoji;
    if (myReactions.isNotEmpty) {
      displayEmoji = myReactions.first;
    } else {
      displayEmoji = reactionCounts.entries
          .reduce((a, b) => a.value > b.value ? a : b)
          .key;
    }

    return _ReactionChip(
      reactionId: displayEmoji,
      count: reactionCounts[displayEmoji] ?? 0,
      isSelected: myReactions.contains(displayEmoji),
      tooltipNames: reactionUsers?[displayEmoji],
      onTap: () => onToggleReaction?.call(displayEmoji!),
      onLongPress: onAddReaction,
    );
  }

  Widget _buildFullView() {
    final sortedEntries = reactionCounts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return Container(
      padding: padding ?? const EdgeInsets.symmetric(vertical: 8),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (onAddReaction != null)
            _ReactionAddButton(onTap: onAddReaction!),
          ...sortedEntries.map((entry) {
            return _ReactionChip(
              reactionId: entry.key,
              count: entry.value,
              isSelected: myReactions.contains(entry.key),
              tooltipNames: reactionUsers?[entry.key],
              onTap: () => onToggleReaction?.call(entry.key),
              onLongPress: onAddReaction,
            );
          }),
        ],
      ),
    );
  }
}

class _ReactionChip extends StatefulWidget {
  final String reactionId;
  final int count;
  final bool isSelected;
  final List<String>? tooltipNames;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _ReactionChip({
    required this.reactionId,
    required this.count,
    required this.isSelected,
    required this.onTap,
    this.onLongPress,
    this.tooltipNames,
  });

  @override
  State<_ReactionChip> createState() => _ReactionChipState();
}

class _ReactionChipState extends State<_ReactionChip> {
  int _tapCount = 0;

  void _handleTap() {
    HapticFeedback.selectionClick();
    setState(() => _tapCount += 1);
    widget.onTap();
  }

  @override
  Widget build(BuildContext context) {
    final isMyReaction = widget.isSelected;
    
    final chip = GestureDetector(
      onTap: _handleTap,
      onLongPress: widget.onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isMyReaction 
              ? AppTheme.brightNavy.withValues(alpha: 0.15)
              : AppTheme.navyBlue.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
          border: isMyReaction 
              ? Border.all(color: AppTheme.brightNavy.withValues(alpha: 0.3))
              : null,
          boxShadow: isMyReaction
              ? [
                  BoxShadow(
                    color: AppTheme.brightNavy.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ReactionIcon(reactionId: widget.reactionId, size: 18),
            if (widget.count > 0) ...[
              const SizedBox(width: 4),
              Text(
                widget.count > 99 ? '99+' : '${widget.count}',
                style: GoogleFonts.inter(
                  color: isMyReaction ? AppTheme.brightNavy : AppTheme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ],
        ),
      ),
    )
    .animate(key: ValueKey('tap_$_tapCount'))
    .scale(begin: const Offset(1, 1), end: const Offset(1.1, 1.1), duration: 100.ms, curve: Curves.easeOut)
    .then()
    .scale(begin: const Offset(1.1, 1.1), end: const Offset(1, 1), duration: 150.ms, curve: Curves.easeOutBack);

    final names = widget.tooltipNames;
    if (names == null || names.isEmpty) return chip;

    return Tooltip(
      message: names.take(5).join(', '),
      child: chip,
    );
  }
}

class _ReactionAddButton extends StatelessWidget {
  final VoidCallback onTap;

  const _ReactionAddButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppTheme.navyBlue.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.add_reaction_outlined,
              color: AppTheme.textSecondary,
              size: 20,
            ),
          ],
        ),
      ),
    );
  }
}

class _ReactionIcon extends StatelessWidget {
  final String reactionId;
  final double size;

  const _ReactionIcon({required this.reactionId, this.size = 14});

  @override
  Widget build(BuildContext context) {
    // CDN URL
    if (reactionId.startsWith('https://')) {
      return CachedNetworkImage(
        imageUrl: reactionId,
        width: size,
        height: size,
        fit: BoxFit.contain,
        placeholder: (_, __) => SizedBox(width: size, height: size),
        errorWidget: (_, __, ___) =>
            Icon(Icons.image_not_supported, size: size * 0.8),
      );
    }

    // Local asset
    if (reactionId.startsWith('assets/') || reactionId.startsWith('asset:')) {
      final assetPath = reactionId.startsWith('asset:')
          ? reactionId.replaceFirst('asset:', '')
          : reactionId;

      if (assetPath.endsWith('.svg')) {
        return SvgPicture.asset(assetPath, width: size, height: size);
      }
      return Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
      );
    }

    // Emoji
    return Text(reactionId, style: TextStyle(fontSize: size));
  }
}

// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/post.dart';
import '../../providers/api_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../sojorn_snackbar.dart';
import '../reactions/anchored_reaction_popup.dart';
import '../reactions/reactions_display.dart';

/// Post actions with a vibrant, clear, and energetic design.
///
/// Design Intent:
/// - Actions are clear, tappable, and visually engaging.
/// - Clear state changes: default (energetic) → active (highlighted).
class PostActions extends ConsumerStatefulWidget {
  final Post post;
  final VoidCallback? onChain;
  final VoidCallback? onPostChanged;
  final bool isThreadView;
  final bool showReactions;

  const PostActions({
    super.key,
    required this.post,
    this.onChain,
    this.onPostChanged,
    this.isThreadView = false,
    this.showReactions = false,
  });

  @override
  ConsumerState<PostActions> createState() => _PostActionsState();
}

class _PostActionsState extends ConsumerState<PostActions>
    with SingleTickerProviderStateMixin {
  late bool _isSaved;
  bool _isSaving = false;
  late final AnimationController _saveAnimCtrl;
  late final Animation<double> _saveScale;
  
  // Reaction state
  final Map<String, int> _reactionCounts = {};
  final Set<String> _myReactions = <String>{};

  @override
  void initState() {
    super.initState();
    _isSaved = widget.post.isSaved ?? false;
    _seedReactionState();
    _saveAnimCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _saveScale = TweenSequence<double>([
      TweenSequenceItem(tween: Tween(begin: 1.0, end: 1.3), weight: 40),
      TweenSequenceItem(tween: Tween(begin: 1.3, end: 0.9), weight: 30),
      TweenSequenceItem(tween: Tween(begin: 0.9, end: 1.0), weight: 30),
    ]).animate(CurvedAnimation(parent: _saveAnimCtrl, curve: Curves.easeOut));
  }

  @override
  void didUpdateWidget(covariant PostActions oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.post != oldWidget.post) {
      _isSaved = widget.post.isSaved ?? false;
      _seedReactionState();
    }
  }

  @override
  void dispose() {
    _saveAnimCtrl.dispose();
    super.dispose();
  }

  int get _totalReactionCount => _reactionCounts.values.fold(0, (sum, c) => sum + c);

  void _seedReactionState() {
    _reactionCounts.clear();
    _myReactions.clear();
    if (widget.post.reactions != null) {
      _reactionCounts.addAll(widget.post.reactions!);
    }
    if (widget.post.myReactions != null) {
      _myReactions.addAll(widget.post.myReactions!);
    }
  }

  void _showError(String message) {
    sojornSnackbar.showError(
      context: context,
      message: message,
    );
  }

  Future<void> _toggleSave() async {
    if (_isSaving) return;
    setState(() {
      _isSaving = true;
      _isSaved = !_isSaved;
    });
    _saveAnimCtrl.forward(from: 0);

    final apiService = ref.read(apiServiceProvider);

    try {
      if (_isSaved) {
        await apiService.savePost(widget.post.id);
      } else {
        await apiService.unsavePost(widget.post.id);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isSaved = !_isSaved;
        });
        _showError(e.toString().replaceAll('Exception: ', ''));
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _sharePost() async {
    final handle = widget.post.author?.handle ?? 'sojorn';
    final text = '${widget.post.body}\n\n— @$handle on sojorn';

    try {
      await Share.share(text);
    } catch (e) {
      _showError('Unable to share right now.');
    }
  }

  void _showReactionPicker(Offset tapPosition) {
    showAnchoredReactionPicker(
      context: context,
      tapPosition: tapPosition,
      myReactions: _myReactions,
      reactionCounts: _reactionCounts,
      onReaction: _toggleReaction,
    );
  }

  Future<void> _toggleReaction(String emoji) async {
    final previousCounts = Map<String, int>.from(_reactionCounts);
    final previousMine = Set<String>.from(_myReactions);

    setState(() {
      if (_myReactions.contains(emoji)) {
        _myReactions.remove(emoji);
        final next = (_reactionCounts[emoji] ?? 1) - 1;
        if (next <= 0) {
          _reactionCounts.remove(emoji);
        } else {
          _reactionCounts[emoji] = next;
        }
      } else {
        if (_myReactions.isNotEmpty) {
          final previousEmoji = _myReactions.first;
          _myReactions.clear();
          final prevCount = (_reactionCounts[previousEmoji] ?? 1) - 1;
          if (prevCount <= 0) {
            _reactionCounts.remove(previousEmoji);
          } else {
            _reactionCounts[previousEmoji] = prevCount;
          }
        }
        _myReactions.add(emoji);
        _reactionCounts[emoji] = (_reactionCounts[emoji] ?? 0) + 1;
      }
    });

    try {
      final api = ref.read(apiServiceProvider);
      final response = await api.toggleReaction(widget.post.id, emoji);
      if (!mounted) return;
      final updatedCounts = response['reactions'] as Map<String, dynamic>?;
      final updatedMine = response['my_reactions'] as List<dynamic>?;
      
      if (updatedCounts != null) {
        setState(() {
          _reactionCounts.clear();
          _reactionCounts.addAll(
            updatedCounts.map((key, value) => MapEntry(key, value as int))
          );
        });
      }
      if (updatedMine != null) {
        setState(() {
          _myReactions.clear();
          _myReactions.addAll(updatedMine.map((item) => item.toString()));
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _reactionCounts.clear();
          _reactionCounts.addAll(previousCounts);
          _myReactions.clear();
          _myReactions.addAll(previousMine);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final allowChain = widget.post.allowChain && widget.post.visibility != 'private' && widget.onChain != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.showReactions && _reactionCounts.isNotEmpty)
          ReactionsDisplay(
            reactionCounts: _reactionCounts,
            myReactions: _myReactions,
            onToggleReaction: _toggleReaction,
            onAddReaction: _showReactionPicker,
            mode: ReactionsDisplayMode.full,
          ),
        
        // Engagement summary (reply count + reaction count) — only show if non-zero
        if (!widget.showReactions && _totalReactionCount > 0 || (widget.post.commentCount ?? 0) > 0)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              children: [
                if (_totalReactionCount > 0) ...[
                  Text(
                    '$_totalReactionCount ${_totalReactionCount == 1 ? 'reaction' : 'reactions'}',
                    style: GoogleFonts.inter(fontSize: 12, color: AppTheme.navyText.withValues(alpha: 0.5), fontWeight: FontWeight.w500),
                  ),
                  if ((widget.post.commentCount ?? 0) > 0)
                    Text(' · ', style: TextStyle(color: AppTheme.navyText.withValues(alpha: 0.35))),
                ],
                if ((widget.post.commentCount ?? 0) > 0)
                  Text(
                    '${widget.post.commentCount} ${widget.post.commentCount == 1 ? 'comment' : 'comments'}',
                    style: GoogleFonts.inter(fontSize: 12, color: AppTheme.navyText.withValues(alpha: 0.5), fontWeight: FontWeight.w500),
                  ),
              ],
            ),
          ),

        // Actions row
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            // Left side: Save + Share
            Row(
              children: [
                ScaleTransition(
                  scale: _saveScale,
                  child: IconButton(
                    onPressed: _isSaving ? null : _toggleSave,
                    tooltip: 'Save post',
                    icon: Icon(
                      _isSaved ? Icons.bookmark : Icons.bookmark_border,
                      color: _isSaved ? AppTheme.brightNavy : AppTheme.textSecondary,
                    ),
                    style: IconButton.styleFrom(
                      backgroundColor: AppTheme.navyBlue.withValues(alpha: 0.08),
                      minimumSize: const Size(34, 34),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  onPressed: _sharePost,
                  tooltip: 'Share',
                  icon: Icon(
                    Icons.share_outlined,
                    color: AppTheme.textSecondary,
                  ),
                  style: IconButton.styleFrom(
                    backgroundColor: AppTheme.navyBlue.withValues(alpha: 0.08),
                    minimumSize: const Size(34, 34),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                ),
              ],
            ),

            Row(
              children: [
                ReactionsDisplay(
                  reactionCounts: _reactionCounts,
                  myReactions: _myReactions,
                  onToggleReaction: _toggleReaction,
                  onAddReaction: _showReactionPicker,
                  mode: ReactionsDisplayMode.compact,
                ),
                const SizedBox(width: 6),
                if (allowChain)
                  ElevatedButton.icon(
                    onPressed: widget.onChain,
                    icon: Icon(Icons.reply, size: 18, color: AppTheme.navyBlue),
                    label: Text('Reply', style: TextStyle(color: AppTheme.navyBlue, fontWeight: FontWeight.w600)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppTheme.navyBlue.withValues(alpha: 0.05),
                      foregroundColor: AppTheme.navyBlue,
                      elevation: 0,
                      shadowColor: SojornColors.transparent,
                      minimumSize: const Size(0, 38),
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}

/// Icon-only action button with large touch target.
class _IconActionButton extends StatelessWidget {
  final IconData icon;
  final IconData? activeIcon;
  final VoidCallback? onPressed;
  final bool isActive;
  final bool isLoading;
  final Color? activeColor;

  const _IconActionButton({
    required this.icon,
    this.activeIcon,
    this.onPressed,
    this.isActive = false,
    this.isLoading = false,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveActiveColor = activeColor ?? AppTheme.brightNavy;
    final effectiveDefaultColor = AppTheme.royalPurple;
    final color = isActive ? effectiveActiveColor : effectiveDefaultColor;
    final displayIcon = isActive && activeIcon != null ? activeIcon! : icon;

    return AnimatedOpacity(
      opacity: isLoading ? 0.5 : 1.0,
      duration: const Duration(milliseconds: 200),
      child: IconButton(
        onPressed: onPressed,
        iconSize: 22.0,
        padding: const EdgeInsets.all(8.0),
        constraints: const BoxConstraints(
          minWidth: 44,
          minHeight: 44,
        ),
        icon: Icon(
          displayIcon,
          size: 22.0,
          color: color,
        ),
      ),
    );
  }
}

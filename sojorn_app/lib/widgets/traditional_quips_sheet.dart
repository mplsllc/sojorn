import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'dart:ui';
import 'package:go_router/go_router.dart';

import '../routes/app_routes.dart';
import '../models/post.dart';
import '../models/profile.dart';
import '../models/thread_node.dart';
import '../providers/api_provider.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../theme/tokens.dart';
import '../widgets/media/signed_media_image.dart';
import '../widgets/reactions/reactions_display.dart';
import '../widgets/reactions/reaction_picker.dart';
import '../widgets/composer/composer_bar.dart';
import '../widgets/modals/sanctuary_sheet.dart';
import '../widgets/sojorn_snackbar.dart';
import '../providers/notification_provider.dart';
import 'post/post_body.dart';
import 'post/post_view_mode.dart';

class TraditionalQuipsSheet extends ConsumerStatefulWidget {
  final String postId;
  final int initialQuipCount;
  final VoidCallback? onQuipPosted;
  /// When false (e.g. Quips video feed), shows only "X Comments" + close button
  /// with no Home/Chat/Search navigation icons.
  final bool showNavActions;

  const TraditionalQuipsSheet({
    super.key,
    required this.postId,
    this.initialQuipCount = 0,
    this.onQuipPosted,
    this.showNavActions = true,
  });

  @override
  ConsumerState<TraditionalQuipsSheet> createState() => _TraditionalQuipsSheetState();
}

class _TraditionalQuipsSheetState extends ConsumerState<TraditionalQuipsSheet> {
  List<Post> _allPosts = [];
  ThreadNode? _rootNode;
  Post? _videoPost;
  bool _isLoading = true;
  String? _error;
  
  final TextEditingController _commentController = TextEditingController();
  final FocusNode _commentFocus = FocusNode();
  
  // Replying state
  ThreadNode? _replyingToNode;
  
  // Selection mode for bulk delete
  bool _isSelectionMode = false;
  final Set<String> _selectedCommentIds = {};
  
  // Collapsed state map: commentId -> isCollapsed
  final Set<String> _collapsedIds = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _commentController.dispose();
    _commentFocus.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = ref.read(apiServiceProvider);
      
      // Load the video post to know the author (for pinning rights)
      _videoPost = await api.getPostById(widget.postId);
      
      // Load all comments in the thread
      final posts = await api.getPostChain(widget.postId);
      
      if (mounted) {
        final tree = ThreadNode.buildTree(posts);
        
        // Sort top-level comments: Pinned first, then by creation date
        tree.children.sort((a, b) {
          final aPinned = a.post.pinnedAt != null;
          final bPinned = b.post.pinnedAt != null;
          if (aPinned && !bPinned) return -1;
          if (!aPinned && bPinned) return 1;
          return a.post.createdAt.compareTo(b.post.createdAt);
        });

        setState(() {
          _allPosts = posts;
          _rootNode = tree;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _postComment(String body, String? _) async {
    final api = ref.read(apiServiceProvider);
    await api.publishPost(
      body: body,
      chainParentId: _replyingToNode?.post.id ?? widget.postId,
      allowChain: true,
    );
    _commentFocus.unfocus();
    if (mounted) setState(() => _replyingToNode = null);
    await _loadData();
    widget.onQuipPosted?.call();
    if (mounted) sojornSnackbar.showSuccess(context: context, message: 'Comment posted!');
  }

  void _startReply(ThreadNode node) {
    setState(() {
      _replyingToNode = node;
      _commentFocus.requestFocus();
    });
  }

  void _cancelReply() {
    setState(() {
      _replyingToNode = null;
      _commentController.clear();
      _commentFocus.unfocus();
    });
  }

  Future<void> _deleteComment(String commentId) async {
    try {
      final api = ref.read(apiServiceProvider);
      await api.deletePost(commentId);
      await _loadData();
    } catch (e) {
      if (mounted) {
        sojornSnackbar.showError(context: context, message: 'Delete failed: $e');
      }
    }
  }

  Future<void> _bulkDelete() async {
    if (_selectedCommentIds.isEmpty) return;
    
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: AppTheme.cardSurface,
        title: Text('Delete Comments', style: TextStyle(color: AppTheme.navyBlue)),
        content: Text('Are you sure you want to delete ${_selectedCommentIds.length} comments?', style: TextStyle(color: AppTheme.navyText)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: SojornColors.destructive)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    
    try {
      final api = ref.read(apiServiceProvider);
      for (final id in _selectedCommentIds) {
        await api.deletePost(id);
      }
      
      setState(() {
        _isSelectionMode = false;
        _selectedCommentIds.clear();
      });
      
      await _loadData();
    } catch (e) {
      if (mounted) {
        sojornSnackbar.showError(context: context, message: 'Bulk delete error: $e');
      }
      setState(() => _isLoading = false);
    }
  }

  Future<void> _togglePin(Post comment) async {
    final isPinned = comment.pinnedAt != null;
    try {
      final api = ref.read(apiServiceProvider);
      if (isPinned) {
        await api.unpinPost(comment.id);
      } else {
        await api.pinPost(comment.id);
      }
      await _loadData();
    } catch (e) {
      if (mounted) {
        sojornSnackbar.showError(context: context, message: 'Pin action failed: $e');
      }
    }
  }

  void _toggleCollapse(String id) {
    setState(() {
      if (_collapsedIds.contains(id)) {
        _collapsedIds.remove(id);
      } else {
        _collapsedIds.add(id);
      }
    });
  }

  void _toggleSelection(String id) {
    setState(() {
      if (_selectedCommentIds.contains(id)) {
        _selectedCommentIds.remove(id);
        if (_selectedCommentIds.isEmpty) _isSelectionMode = false;
      } else {
        _selectedCommentIds.add(id);
        _isSelectionMode = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.95,
      minChildSize: 0.6,
      maxChildSize: 0.95,
      snap: true,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: AppTheme.scaffoldBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            boxShadow: [
              BoxShadow(
                color: SojornColors.overlayScrim,
                blurRadius: 40,
                offset: const Offset(0, -10),
              ),
            ],
          ),
          child: Column(
            children: [
              _buildAppBarHeader(),
              Expanded(
                child: _isLoading && _allPosts.isEmpty 
                  ? Center(child: CircularProgressIndicator(color: AppTheme.brightNavy))
                  : _buildCommentList(scrollController),
              ),
              if (!_isSelectionMode) _buildInputArea(),
            ],
          ),
        );
      },
    );
  }

  Widget _buildAppBarHeader() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          bottom: BorderSide(
            color: AppTheme.egyptianBlue.withValues(alpha: 0.1),
            width: 1,
          ),
        ),
      ),
      child: Column(
        children: [
          // Drag Handle
          Container(
            width: 40,
            height: 4,
            margin: const EdgeInsets.only(top: 12, bottom: 4),
            decoration: BoxDecoration(
              color: AppTheme.navyBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
            child: Row(
              children: [
                if (_isSelectionMode) ...[
                  IconButton(
                    onPressed: () => setState(() {
                      _isSelectionMode = false;
                      _selectedCommentIds.clear();
                    }),
                    icon: Icon(Icons.close, color: AppTheme.navyBlue),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '${_selectedCommentIds.length} Selected',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: AppTheme.brightNavy,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, color: SojornColors.destructive),
                    onPressed: _bulkDelete,
                  ),
                ] else if (widget.showNavActions) ...[
                  // Full thread header with nav buttons (used in regular post view)
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.arrow_back, color: AppTheme.navyBlue),
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Thread',
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w700,
                      fontSize: 18,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => context.go(AppRoutes.homeAlias),
                    icon: Icon(Icons.home_outlined, color: AppTheme.navyBlue),
                  ),
                  IconButton(
                    onPressed: () {},
                    icon: Icon(Icons.search, color: AppTheme.navyBlue),
                  ),
                  IconButton(
                    onPressed: () => context.go(AppRoutes.secureChat),
                    icon: Consumer(
                      builder: (context, ref, child) {
                        final badge = ref.watch(currentBadgeProvider);
                        return Badge(
                          label: Text(badge.messageCount.toString()),
                          isLabelVisible: badge.messageCount > 0,
                          backgroundColor: AppTheme.brightNavy,
                          child: Icon(Icons.chat_bubble_outline, color: AppTheme.navyBlue),
                        );
                      },
                    ),
                  ),
                ] else ...[
                  // Clean Quips-style header: "X Comments" + close X
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 12),
                      child: Text(
                        '$_commentCount Comment${_commentCount == 1 ? '' : 's'}',
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w700,
                          fontSize: 17,
                          color: AppTheme.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: Icon(Icons.close, color: AppTheme.navyBlue),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  int get _commentCount => _rootNode?.totalCount ?? widget.initialQuipCount;

  Widget _buildCommentList(ScrollController scrollController) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, color: SojornColors.destructive, size: 48),
              const SizedBox(height: 16),
              Text('Error: $_error', style: TextStyle(color: AppTheme.navyText), textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }

    if (_rootNode == null || _rootNode!.children.isEmpty) {
      if (_isLoading) return Center(child: CircularProgressIndicator(color: AppTheme.brightNavy));
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.chat_bubble_outline, size: 48, color: AppTheme.navyBlue.withValues(alpha: 0.1)),
            const SizedBox(height: 16),
            Text(
              'No messages yet',
              style: GoogleFonts.inter(color: AppTheme.textSecondary.withValues(alpha: 0.5), fontSize: 16),
            ),
          ],
        ),
      );
    }

    final items = _flattenTree(_rootNode!.children);

    return ListView.builder(
      controller: scrollController,
      padding: const EdgeInsets.symmetric(vertical: 20),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final node = items[index];
        return _CommentTile(
          node: node,
          videoAuthorId: _videoPost?.authorId,
          isPinned: node.post.pinnedAt != null,
          isSelected: _selectedCommentIds.contains(node.post.id),
          isCollapsed: _collapsedIds.contains(node.post.id),
          onCollapse: () => _toggleCollapse(node.post.id),
          onSelect: () => _toggleSelection(node.post.id),
          onReply: () => _startReply(node),
          onDelete: () => _deleteComment(node.post.id),
          onPin: () => _togglePin(node.post),
          onReport: () => SanctuarySheet.show(context, node.post),
          onReaction: (emoji) => _toggleReaction(node.post.id, emoji),
        );
      },
    );
  }

  List<ThreadNode> _flattenTree(List<ThreadNode> nodes) {
    List<ThreadNode> flat = [];
    for (final node in nodes) {
      flat.add(node);
      if (!_collapsedIds.contains(node.post.id)) {
        flat.addAll(_flattenTree(node.children));
      }
    }
    return flat;
  }

  Future<void> _toggleReaction(String postId, String emoji) async {
    try {
      final api = ref.read(apiServiceProvider);
      await api.toggleReaction(postId, emoji);
      await _loadData();
    } catch (e) {
      if (mounted) sojornSnackbar.showError(context: context, message: 'Reaction failed: $e');
    }
  }

  Widget _buildInputArea() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_replyingToNode != null)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            color: AppTheme.brightNavy.withValues(alpha: 0.05),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Icon(Icons.reply, size: 14, color: AppTheme.brightNavy),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Replying to @${_replyingToNode!.post.author?.handle}',
                        style: TextStyle(color: AppTheme.navyBlue, fontSize: 12, fontWeight: FontWeight.w600),
                      ),
                      if (_replyingToNode!.post.body.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          _replyingToNode!.post.body,
                          style: TextStyle(
                            color: AppTheme.navyText.withValues(alpha: 0.6),
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                GestureDetector(
                  onTap: _cancelReply,
                  child: Icon(Icons.close, size: 14, color: AppTheme.textSecondary),
                ),
              ],
            ),
          ),
        Container(
          padding: EdgeInsets.fromLTRB(16, 12, 16,
              (MediaQuery.of(context).viewInsets.bottom > 0
                  ? MediaQuery.of(context).viewInsets.bottom
                  : MediaQuery.of(context).padding.bottom) + 16),
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            border: Border(top: BorderSide(color: AppTheme.egyptianBlue.withValues(alpha: 0.1))),
          ),
          child: ComposerBar(
            config: ComposerConfig.comment,
            onSend: _postComment,
            externalController: _commentController,
            focusNode: _commentFocus,
          ),
        ),
      ],
    );
  }
}

class _CommentTile extends StatelessWidget {
  final ThreadNode node;
  final String? videoAuthorId;
  final bool isPinned;
  final bool isSelected;
  final bool isCollapsed;
  final VoidCallback onCollapse;
  final VoidCallback onSelect;
  final VoidCallback onReply;
  final VoidCallback onDelete;
  final VoidCallback onPin;
  final VoidCallback onReport;
  final Function(String) onReaction;

  const _CommentTile({
    required this.node,
    this.videoAuthorId,
    this.isPinned = false,
    this.isSelected = false,
    this.isCollapsed = false,
    required this.onCollapse,
    required this.onSelect,
    required this.onReply,
    required this.onDelete,
    required this.onPin,
    required this.onReport,
    required this.onReaction,
  });

  @override
  Widget build(BuildContext context) {
    final currentUserId = AuthService.instance.currentUser?.id;
    final isMyComment = node.post.authorId == currentUserId;
    final isVideoAuthor = videoAuthorId == currentUserId;
    
    final double indent = (node.depth - 1) * 24.0;
    
    return Padding(
      padding: EdgeInsets.only(left: 16 + indent, right: 16, bottom: 16),
      child: GestureDetector(
        onLongPress: onSelect,
        onTap: isSelected ? onSelect : null,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: isSelected ? AppTheme.brightNavy.withValues(alpha: 0.08) : AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: isSelected ? AppTheme.brightNavy.withValues(alpha: 0.3) : AppTheme.egyptianBlue.withValues(alpha: 0.1),
              width: isSelected ? 2 : 1,
            ),
            boxShadow: [
              if (!isSelected)
                BoxShadow(
                  color: SojornColors.basicBlack.withValues(alpha: 0.02),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
            ],
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildAvatar(node.post.author),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          node.post.author?.displayName ?? node.post.author?.handle ?? 'unknown',
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                        if (isPinned) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.push_pin, size: 13, color: AppTheme.brightNavy),
                          const SizedBox(width: 4),
                          Text(
                            'Pinned', 
                            style: GoogleFonts.inter(
                              fontSize: 12, 
                              color: AppTheme.brightNavy,
                              fontWeight: FontWeight.w800,
                            )
                          ),
                        ],
                        const Spacer(),
                        _buildMenu(context, isMyComment, isVideoAuthor),
                      ],
                    ),
                    const SizedBox(height: 6),
                    PostBody(
                      text: node.post.body,
                      bodyFormat: node.post.bodyFormat,
                      backgroundId: node.post.backgroundId,
                      mode: PostViewMode.feed,
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Text(
                          timeago.format(node.post.createdAt, locale: 'en_short'),
                          style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.5), fontSize: 13),
                        ),
                        const SizedBox(width: 24),
                        GestureDetector(
                          onTap: onReply,
                          child: Text(
                            'Reply', 
                            style: TextStyle(color: AppTheme.brightNavy, fontSize: 13, fontWeight: FontWeight.w800)
                          ),
                        ),
                        if (node.hasChildren) ...[
                          const SizedBox(width: 24),
                          GestureDetector(
                            onTap: onCollapse,
                            child: Text(
                              isCollapsed ? 'Show replies (${node.totalDescendants})' : 'Hide replies',
                              style: TextStyle(color: AppTheme.egyptianBlue, fontSize: 13, fontWeight: FontWeight.w700),
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (node.post.reactions != null && node.post.reactions!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 14),
                        child: ReactionsDisplay(
                          reactionCounts: node.post.reactions!,
                          myReactions: node.post.myReactions?.toSet() ?? {},
                          onToggleReaction: onReaction,
                          onAddReaction: (pos) => _showReactionPicker(context, pos),
                          mode: ReactionsDisplayMode.compact,
                        ),
                      ),
                  ],
                ),
              ),
              Column(
                children: [
                   IconButton(
                    icon: Icon(
                      node.post.isLiked == true ? Icons.favorite : Icons.favorite_border,
                      size: 20,
                      color: node.post.isLiked == true ? SojornColors.destructive : AppTheme.textSecondary.withValues(alpha: 0.2),
                    ),
                    onPressed: () => onReaction('❤️'),
                    visualDensity: VisualDensity.compact,
                  ),
                  if (node.post.likeCount != null && node.post.likeCount! > 0)
                    Text(
                      '${node.post.likeCount}',
                      style: TextStyle(color: AppTheme.textSecondary.withValues(alpha: 0.6), fontSize: 13, fontWeight: FontWeight.w700),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvatar(Profile? author) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: AppTheme.navyBlue.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.egyptianBlue.withValues(alpha: 0.1)),
      ),
      child: author?.avatarUrl != null && author!.avatarUrl!.isNotEmpty
        ? ClipRRect(
            borderRadius: BorderRadius.circular(20),
            child: SignedMediaImage(url: author.avatarUrl!, width: 40, height: 40, fit: BoxFit.cover),
          )
        : Center(child: Text(author?.displayName?.isNotEmpty == true ? author!.displayName![0].toUpperCase() : '?', style: TextStyle(color: AppTheme.navyBlue, fontSize: 16, fontWeight: FontWeight.w800))),
    );
  }

  Widget _buildMenu(BuildContext context, bool isMyComment, bool isVideoAuthor) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_horiz, size: 22, color: AppTheme.textSecondary.withValues(alpha: 0.4)),
      padding: EdgeInsets.zero,
      color: AppTheme.cardSurface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppTheme.egyptianBlue.withValues(alpha: 0.1)),
      ),
      itemBuilder: (context) => [
        if (isVideoAuthor)
          PopupMenuItem(
            value: 'pin', 
            child: Row(
              children: [
                Icon(Icons.push_pin_outlined, size: 18, color: AppTheme.navyBlue),
                const SizedBox(width: 12),
                Text(isPinned ? 'Unpin' : 'Pin', style: TextStyle(color: AppTheme.textPrimary)),
              ],
            )
          ),
        if (isMyComment || isVideoAuthor)
          PopupMenuItem(
            value: 'delete', 
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 18, color: SojornColors.destructive),
                const SizedBox(width: 12),
                const Text('Delete', style: TextStyle(color: SojornColors.destructive)),
              ],
            )
          ),
        PopupMenuItem(
          value: 'report', 
          child: Row(
            children: [
              Icon(Icons.flag_outlined, size: 18, color: AppTheme.navyBlue),
              const SizedBox(width: 12),
              Text('Report', style: TextStyle(color: AppTheme.textPrimary)),
            ],
          )
        ),
        PopupMenuItem(
          value: 'select', 
          child: Row(
            children: [
              Icon(Icons.check_circle_outline, size: 18, color: AppTheme.navyBlue),
              const SizedBox(width: 12),
              Text('Select multiple', style: TextStyle(color: AppTheme.textPrimary)),
            ],
          )
        ),
      ],
      onSelected: (value) {
        switch (value) {
          case 'pin': onPin(); break;
          case 'delete': onDelete(); break;
          case 'report': onReport(); break;
          case 'select': onSelect(); break;
        }
      },
    );
  }

  void _showReactionPicker(BuildContext context, Offset tapPosition) {
    const quickEmojis = ['❤️', '👍', '😂', '😮', '😢', '😡', '🎉', '🔥'];
    final screenSize = MediaQuery.of(context).size;
    final Set<String> mine = node.post.myReactions?.toSet() ?? {};

    const pillWidth = 320.0;
    const pillHeight = 52.0;
    double left = tapPosition.dx - pillWidth / 2;
    double top = tapPosition.dy - pillHeight - 12;
    left = left.clamp(8.0, screenSize.width - pillWidth - 8);
    top = top.clamp(8.0, screenSize.height - pillHeight - 8);

    showDialog<void>(
      context: context,
      barrierColor: Colors.black12,
      builder: (ctx) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => Navigator.pop(ctx),
        child: Stack(
          children: [
            Positioned(
              left: left,
              top: top,
              child: GestureDetector(
                onTap: () {},
                child: Material(
                  elevation: 10,
                  borderRadius: BorderRadius.circular(32),
                  color: AppTheme.cardSurface,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        ...quickEmojis.map((emoji) {
                          final isActive = mine.contains(emoji);
                          return GestureDetector(
                            onTap: () {
                              Navigator.pop(ctx);
                              onReaction(emoji);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 120),
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              padding: const EdgeInsets.all(4),
                              decoration: isActive
                                  ? BoxDecoration(
                                      color: AppTheme.brightNavy.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    )
                                  : null,
                              child: Text(emoji, style: const TextStyle(fontSize: 26)),
                            ),
                          );
                        }),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

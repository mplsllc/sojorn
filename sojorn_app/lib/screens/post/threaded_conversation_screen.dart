import 'dart:ui';
import 'package:flutter/material.dart';
import '../../routes/app_routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/settings_provider.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../widgets/reactions/reaction_picker.dart';
import '../../widgets/reactions/reactions_display.dart';
import '../../models/post.dart';
import '../../providers/api_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/post/interactive_reply_block.dart';
import '../../widgets/media/signed_media_image.dart';
import '../compose/compose_screen.dart';
import '../../services/notification_service.dart';
import '../../widgets/post/post_body.dart';
import '../../widgets/post/post_link_preview.dart';
import '../../widgets/post/post_view_mode.dart';
import '../../widgets/post/post_media.dart';
import '../home/full_screen_shell.dart';
import 'package:share_plus/share_plus.dart';


class ThreadedConversationScreen extends ConsumerStatefulWidget {
  final String rootPostId;
  final Post? rootPost;

  const ThreadedConversationScreen({
    super.key,
    required this.rootPostId,
    this.rootPost,
  });

  @override
  ConsumerState<ThreadedConversationScreen> createState() => _ThreadedConversationScreenState();
}

class _ThreadedConversationScreenState extends ConsumerState<ThreadedConversationScreen>
    with TickerProviderStateMixin {
  FocusContext? _focusContext;
  bool _isLoading = true;
  String? _error;
  bool _isTransitioning = false;
  final Map<String, Map<String, int>> _reactionCountsByPost = {};
  final Map<String, Set<String>> _myReactionsByPost = {};
  final Map<String, Map<String, List<String>>> _reactionUsersByPost = {};
  final Map<String, bool> _likedByPost = {};
  final Map<String, bool> _savedByPost = {};
  final Set<String> _nsfwRevealed = {};
  bool _initialLoadDone = false;

  bool _shouldBlurPost(Post post) {
    if (!post.isNsfw || _nsfwRevealed.contains(post.id)) return false;
    final settings = ref.read(settingsProvider);
    // Always blur if user hasn't opted into NSFW content
    if (!(settings.user?.nsfwEnabled ?? false)) return true;
    // If opted in, respect the blur toggle
    return settings.user?.nsfwBlurEnabled ?? true;
  }

  late AnimationController _slideController;
  late AnimationController _fadeController;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    NotificationService.instance.activePostId = widget.rootPostId;
    _initializeAnimations();

    if (widget.rootPost != null) {
      _focusContext = FocusContext(
        targetPost: widget.rootPost!,
        children: const [],
      );
      _seedReactionState(_focusContext!);
    }

    _loadFocusContext();
  }

  void _initializeAnimations() {
    _slideController = AnimationController(
      duration: const Duration(milliseconds: 520),
      vsync: this,
    );

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 360),
      vsync: this,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.12),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _slideController,
      curve: Curves.easeOutBack,
    ));

    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeIn,
    );
  }

  @override
  void dispose() {
    NotificationService.instance.activePostId = null;
    _slideController.dispose();
    _fadeController.dispose();
    super.dispose();
  }

  Future<void> _loadFocusContext() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = ref.read(apiServiceProvider);
      final focusContext = await api.getPostFocusContext(widget.rootPostId);

      if (mounted) {
        setState(() {
          _focusContext = focusContext;
          _isLoading = false;
        });

        _seedReactionState(focusContext);

        // Only animate on initial load, not on reload after posting
        if (!_initialLoadDone) {
          _initialLoadDone = true;
          _slideController.forward(from: 0);
          _fadeController.forward(from: 0);
        }
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

  Future<void> _navigateToPost(String postId) async {
    if (_isTransitioning || _focusContext?.targetPost.id == postId) return;
    
    // Instead of just flipping state, we push a new route to maintain history
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ThreadedConversationScreen(rootPostId: postId),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FullScreenShell(
      title: AnimatedSwitcher(
        duration: const Duration(milliseconds: 250),
        child: Text(
          _focusContext != null ? 'Thread' : 'Loading...',
          key: ValueKey(_focusContext?.targetPost.id),
          style: GoogleFonts.inter(
            color: AppTheme.textPrimary,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading && _focusContext == null) {
      return _buildLoadingState();
    }

    if (_error != null) {
      return _buildErrorState();
    }

    if (_focusContext == null) {
      return _buildEmptyState();
    }

    final content = RefreshIndicator(
      onRefresh: _loadFocusContext,
      color: AppTheme.brightNavy,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 280),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          child: Column(
            key: ValueKey(_focusContext!.targetPost.id),
            children: [
              if (_focusContext!.parentPost != null) ...[
                _buildAnchorZone(_focusContext!.parentPost!),
              ],

              // Zone B: The Stage (Current Focal Post)
              _buildStageZone(_focusContext!.targetPost),
              const SizedBox(height: 26),

              // Zone C: The Pit (Replies)
              _buildPitZone(_focusContext!.children),
              const SizedBox(height: 32),
            ],
          ),
        ),
      ),
    );

    return Stack(
      children: [
        content,
        if (_isTransitioning)
          Positioned(
            top: 0,
            left: 16,
            right: 16,
            child: LinearProgressIndicator(
              minHeight: 3,
              color: AppTheme.brightNavy,
              backgroundColor: AppTheme.navyBlue.withValues(alpha: 0.08),
            ),
          ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppTheme.brightNavy),
          const SizedBox(height: 16),
          Text(
            'Loading thread focus...',
            style: GoogleFonts.inter(
              color: AppTheme.textSecondary,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.error, color: SojornColors.destructive, size: 48),
            const SizedBox(height: 16),
            Text(
              'Failed to load conversation',
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: GoogleFonts.inter(
                color: AppTheme.textSecondary,
                fontSize: 14,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadFocusContext,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppTheme.brightNavy,
                foregroundColor: SojornColors.basicWhite,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Text(
        'Conversation not found',
        style: GoogleFonts.inter(
          color: AppTheme.textSecondary,
          fontSize: 16,
        ),
      ),
    );
  }

  Widget _buildAnchorZone(Post parentPost) {
    return SlideTransition(
      position: _slideAnimation,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
        child: GestureDetector(
          onTap: () => _navigateToPost(parentPost.id),
          child: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              // Rounded top corners, flat bottom
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(20),
                topRight: Radius.circular(20),
              ),
              // Gradient from darker top to lighter bottom
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppTheme.navyBlue.withValues(alpha: 0.25),  // Darker at top
                  AppTheme.navyBlue.withValues(alpha: 0.12),  // Lighter at bottom
                  SojornColors.transparent,                         // Fade to transparent
                ],
                stops: const [0.0, 0.6, 1.0],
              ),
              // Subtle border at the top
              border: Border(
                top: BorderSide(
                  color: AppTheme.brightNavy.withValues(alpha: 0.5),
                  width: 2,
                ),
              ),
            ),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
              child: Row(
                children: [
                  _buildCompactAvatar(parentPost),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'In reply to',
                          style: GoogleFonts.inter(
                            color: AppTheme.textSecondary.withValues(alpha: 0.9),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            letterSpacing: 0.6,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '@${parentPost.author?.handle ?? parentPost.author?.displayName ?? 'anonymous'}',
                          style: GoogleFonts.inter(
                            color: AppTheme.navyBlue.withValues(alpha: 0.95),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        if (_shouldBlurPost(parentPost))
                          ImageFiltered(
                            imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                            child: Text(
                              parentPost.body,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.inter(
                                color: AppTheme.navyText.withValues(alpha: 0.8),
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          )
                        else
                        Text(
                          parentPost.body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.inter(
                            color: AppTheme.navyText.withValues(alpha: 0.8),
                            fontSize: 12,
                            height: 1.3,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 6),
                        ReactionsDisplay(
                          reactionCounts: _reactionCountsFor(parentPost),
                          myReactions: _myReactionsFor(parentPost),
                          onToggleReaction: (emoji) => _toggleReaction(parentPost.id, emoji),
                          onAddReaction: (pos) => _openReactionPicker(parentPost.id, pos),
                          mode: ReactionsDisplayMode.compact,
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: AppTheme.brightNavy.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.arrow_upward,
                      size: 18,
                      color: AppTheme.brightNavy,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ).animate().slideY(begin: -0.08, end: 0, duration: 220.ms),
    );
  }

  Widget _buildStageZone(Post focalPost) {
    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(26),
            border: Border.all(
              color: AppTheme.brightNavy.withValues(alpha: 0.35),
              width: 1.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppTheme.brightNavy.withValues(alpha: 0.08),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                _buildStageHeader(focalPost),
                const SizedBox(height: 16),
                if (_shouldBlurPost(focalPost)) ...[
                  ClipRect(
                    child: ImageFiltered(
                      imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                      child: _buildStageContent(focalPost),
                    ),
                  ),
                  if (focalPost.imageUrl != null || focalPost.videoUrl != null || focalPost.thumbnailUrl != null) ...[
                    const SizedBox(height: 16),
                    ClipRect(
                      child: ImageFiltered(
                        imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                        child: PostMedia(post: focalPost, mode: PostViewMode.detail),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () => setState(() => _nsfwRevealed.add(focalPost.id)),
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                      decoration: BoxDecoration(
                        color: AppTheme.nsfwWarningBg,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.nsfwWarningBorder),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.visibility_off, size: 18, color: AppTheme.nsfwWarningIcon),
                          const SizedBox(width: 8),
                          Text('Sensitive Content — Tap to reveal',
                            style: TextStyle(color: AppTheme.nsfwWarningText, fontWeight: FontWeight.w600, fontSize: 13)),
                        ],
                      ),
                    ),
                  ),
                ] else ...[
                  _buildStageContent(focalPost),
                  if (focalPost.imageUrl != null || focalPost.videoUrl != null || focalPost.thumbnailUrl != null) ...[
                    const SizedBox(height: 16),
                    PostMedia(
                      post: focalPost,
                      mode: PostViewMode.detail,
                    ),
                  ],
                ],

                const SizedBox(height: 20),
                _buildStageActions(focalPost),
              ],
            ),
          ),
        ),
      ),
    ).animate().fadeIn(duration: 480.ms).scale(begin: const Offset(0.98, 0.98));
  }

  Widget _buildStageHeader(Post post) {
    return Row(
      children: [
        _buildAvatar(post),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                post.author?.displayName ?? 'Anonymous',
                style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '@${post.author?.handle ?? 'anonymous'}',
                style: GoogleFonts.inter(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        if (_focusContext!.children.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppTheme.egyptianBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.chat_bubble_outline,
                  size: 18,
                  color: AppTheme.egyptianBlue,
                ),
                const SizedBox(width: 6),
                Text(
                  '${_focusContext!.children.length} ${_focusContext!.children.length == 1 ? 'reply' : 'replies'}',
                  style: GoogleFonts.inter(
                    color: AppTheme.egyptianBlue,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildStageContent(Post post) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PostBody(
          text: post.body,
          bodyFormat: post.bodyFormat,
          backgroundId: post.backgroundId,
          mode: PostViewMode.detail,
          hideUrls: post.hasLinkPreview,
        ),
        // Link preview card after post body
        if (post.hasLinkPreview) ...[
          const SizedBox(height: 8),
          PostLinkPreview(
            post: post,
            mode: PostViewMode.detail,
          ),
        ],
      ],
    );
  }

  Widget _buildStageMedia(String imageUrl) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 420),
        child: SizedBox(
          width: double.infinity,
          child: SignedMediaImage(
            url: imageUrl,
            fit: BoxFit.cover,
          ),
        ),
      ),
    );
  }

  Widget _buildStageActions(Post post) {
    final isLiked = _likedByPost[post.id] ?? (post.isLiked ?? false);
    final isSaved = _savedByPost[post.id] ?? (post.isSaved ?? false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Reactions section - full width like main post
        ReactionsDisplay(
          reactionCounts: _reactionCountsFor(post),
          myReactions: _myReactionsFor(post),
          reactionUsers: _reactionUsersFor(post),
          onToggleReaction: (emoji) => _toggleReaction(post.id, emoji),
          onAddReaction: (pos) => _openReactionPicker(post.id, pos),
          mode: ReactionsDisplayMode.full,
        ),
        const SizedBox(height: 16),
        // Actions row - left aligned
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: post.allowChain
                    ? () {
                        _openReplyComposer(post);
                      }
                    : null,
                icon: const Icon(Icons.reply, size: 18),
                label: const Text('Reply'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.navyBlue.withValues(alpha: 0.05),
                  foregroundColor: AppTheme.navyBlue,
                  elevation: 0,
                  shadowColor: SojornColors.transparent,
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            IconButton(
              onPressed: () => _sharePost(post),
              icon: Icon(
                Icons.share_outlined,
                color: AppTheme.textSecondary,
              ),
              style: IconButton.styleFrom(
                backgroundColor: AppTheme.navyBlue.withValues(alpha: 0.05),
                minimumSize: const Size(44, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(
              onPressed: () => _toggleSave(post),
              icon: Icon(
                isSaved ? Icons.bookmark : Icons.bookmark_border,
                color: isSaved ? AppTheme.brightNavy : AppTheme.textSecondary,
              ),
              style: IconButton.styleFrom(
                backgroundColor: AppTheme.navyBlue.withValues(alpha: 0.05),
                minimumSize: const Size(44, 44),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _openReplyComposer(Post post) async {
    final result = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (context) => ComposeScreen(chainParentPost: post),
      ),
    );
    // Reset focus so the underlying screen is interactive on web
    FocusManager.instance.primaryFocus?.unfocus();
    if (result == true) {
      _loadFocusContext();
    }
  }

  Future<void> _toggleLike(Post post) async {
    final current = _likedByPost[post.id] ?? (post.isLiked ?? false);
    setState(() {
      _likedByPost[post.id] = !current;
    });
    try {
      final api = ref.read(apiServiceProvider);
      if (!current) {
        await api.appreciatePost(post.id);
      } else {
        await api.unappreciatePost(post.id);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _likedByPost[post.id] = current;
      });
    }
  }

  Future<void> _toggleSave(Post post) async {
    final current = _savedByPost[post.id] ?? (post.isSaved ?? false);
    setState(() {
      _savedByPost[post.id] = !current;
    });
    try {
      final api = ref.read(apiServiceProvider);
      if (!current) {
        await api.savePost(post.id);
      } else {
        await api.unsavePost(post.id);
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _savedByPost[post.id] = current;
      });
    }
  }

  Widget _buildPitZone(List<Post> children) {
    if (children.isEmpty) {
      return SlideTransition(
        position: _slideAnimation,
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: Container(
            margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: AppTheme.cardSurface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppTheme.navyBlue.withValues(alpha: 0.1),
                width: 1,
              ),
            ),
            child: Center(
              child: Text(
                'No replies yet',
                style: GoogleFonts.inter(
                  color: AppTheme.textSecondary,
                  fontSize: 14,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return SlideTransition(
      position: _slideAnimation,
      child: FadeTransition(
        opacity: _fadeAnimation,
        child: Container(
          margin: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Dashboard header
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppTheme.navyBlue.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: AppTheme.navyBlue.withValues(alpha: 0.1),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.chat_bubble_outline,
                      color: AppTheme.brightNavy,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${children.length} ${children.length == 1 ? 'Reply' : 'Replies'}',
                      style: GoogleFonts.inter(
                        color: AppTheme.navyBlue,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Reply chains as grid (3 per row)
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.8,
                ),
                itemCount: children.length,
                itemBuilder: (context, index) {
                  final post = children[index];
                  return _buildDashboardReplyItem(post, index);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardReplyItem(Post post, int index) {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppTheme.navyBlue.withValues(alpha: 0.08),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.navyBlue.withValues(alpha: 0.04),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: SojornColors.transparent,
        child: InkWell(
          onTap: () => _navigateToPost(post.id),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Reply header with menu button
                Row(
                  children: [
                    Container(
                      width: 24,
                      height: 24,
                      decoration: BoxDecoration(
                        color: AppTheme.brightNavy.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Center(
                        child: Text(
                          (post.author?.displayName?.isNotEmpty == true) 
                              ? post.author!.displayName.characters.first.toUpperCase()
                              : 'A',
                          style: GoogleFonts.inter(
                            color: AppTheme.brightNavy,
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            post.author?.displayName ?? 'Anonymous',
                            style: GoogleFonts.inter(
                              color: AppTheme.navyBlue,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            timeago.format(post.createdAt),
                            style: GoogleFonts.inter(
                              color: AppTheme.textSecondary,
                              fontSize: 9,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Menu button
                    Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppTheme.navyBlue.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        Icons.more_horiz,
                        size: 14,
                        color: AppTheme.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Reply content
                Expanded(
                  child: _shouldBlurPost(post)
                    ? GestureDetector(
                        onTap: () => setState(() => _nsfwRevealed.add(post.id)),
                        child: ImageFiltered(
                          imageFilter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                          child: Text(
                            post.body,
                            style: GoogleFonts.inter(
                              color: AppTheme.navyText,
                              fontSize: 11,
                              height: 1.3,
                            ),
                            maxLines: 4,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                    : Text(
                        post.body,
                        style: GoogleFonts.inter(
                          color: AppTheme.navyText,
                          fontSize: 11,
                          height: 1.3,
                        ),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                ),
                const SizedBox(height: 8),
                // Reply actions
                Row(
                  children: [
                    // Compact reactions display
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const NeverScrollableScrollPhysics(),
                        child: ReactionsDisplay(
                          reactionCounts: _reactionCountsFor(post),
                          myReactions: _myReactionsFor(post),
                          onToggleReaction: (emoji) => _toggleReaction(post.id, emoji),
                          onAddReaction: (pos) => _openReactionPicker(post.id, pos),
                          mode: ReactionsDisplayMode.compact,
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: AppTheme.brightNavy.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'View',
                        style: GoogleFonts.inter(
                          color: AppTheme.brightNavy,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    ).animate(delay: (index * 50).ms)
      .fadeIn(duration: 300.ms, curve: Curves.easeOutCubic)
      .scale(begin: const Offset(0.95, 0.95), end: const Offset(1, 1));
  }

  void _toggleReaction(String postId, String emoji) {
    final counts = _reactionCountsByPost.putIfAbsent(postId, () => {});
    final mine = _myReactionsByPost.putIfAbsent(postId, () => <String>{});
    final previousCounts = Map<String, int>.from(counts);
    final previousMine = Set<String>.from(mine);

    setState(() {
      if (mine.contains(emoji)) {
        mine.remove(emoji);
        final next = (counts[emoji] ?? 1) - 1;
        if (next <= 0) {
          counts.remove(emoji);
        } else {
          counts[emoji] = next;
        }
      } else {
        if (mine.isNotEmpty) {
          final previousEmoji = mine.first;
          mine.clear();
          final prevCount = (counts[previousEmoji] ?? 1) - 1;
          if (prevCount <= 0) {
            counts.remove(previousEmoji);
          } else {
            counts[previousEmoji] = prevCount;
          }
        }
        mine.add(emoji);
        counts[emoji] = (counts[emoji] ?? 0) + 1;
      }
    });

    _persistReaction(postId, emoji, previousCounts, previousMine);
  }

  Post? _findPostById(String postId) {
    if (widget.rootPost?.id == postId) return widget.rootPost;
    
    // Search in focus context
    if (_focusContext != null) {
      if (_focusContext!.targetPost.id == postId) return _focusContext!.targetPost;
      for (final post in _focusContext!.children) {
        if (post.id == postId) return post;
      }
    }
    
    return null;
  }

  Future<void> _openReactionPicker(String postId, Offset tapPosition) async {
    const quickEmojis = ['❤️', '👍', '😂', '😮', '😢', '😡', '🎉', '🔥'];
    final screenSize = MediaQuery.of(context).size;
    final myReactions = _myReactionsByPost[postId] ?? <String>{};

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
                      children: quickEmojis.map((emoji) {
                        final isActive = myReactions.contains(emoji);
                        return GestureDetector(
                          onTap: () {
                            Navigator.pop(ctx);
                            _toggleReaction(postId, emoji);
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
                      }).toList(),
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

  void _seedReactionState(FocusContext focusContext) {
    _seedReactionsForPost(focusContext.targetPost);
    if (focusContext.parentPost != null) {
      _seedReactionsForPost(focusContext.parentPost!);
    }
    for (final post in focusContext.children) {
      _seedReactionsForPost(post);
    }
  }

  void _seedReactionsForPost(Post post) {
    if (post.reactions != null) {
      _reactionCountsByPost.putIfAbsent(
        post.id,
        () => Map<String, int>.from(post.reactions!),
      );
    }
    if (post.myReactions != null) {
      _myReactionsByPost.putIfAbsent(post.id, () => post.myReactions!.toSet());
    }
    if (post.reactionUsers != null) {
      _reactionUsersByPost.putIfAbsent(
        post.id,
        () => Map<String, List<String>>.from(post.reactionUsers!),
      );
    }
  }

  Map<String, int> _reactionCountsFor(Post post) {
    // Prefer local state for immediate updates after toggle reactions
    final localState = _reactionCountsByPost[post.id];
    if (localState != null) {
      return localState;
    }
    // Fall back to post model if no local state
    return post.reactions ?? {};
  }

  Set<String> _myReactionsFor(Post post) {
    // Prefer local state for immediate updates after toggle reactions
    final localState = _myReactionsByPost[post.id];
    if (localState != null) {
      return localState;
    }
    // Fall back to post model if no local state
    return post.myReactions?.toSet() ?? <String>{};
  }

  Map<String, List<String>>? _reactionUsersFor(Post post) {
    return _reactionUsersByPost[post.id] ?? post.reactionUsers;
  }

  Future<void> _persistReaction(
    String postId,
    String emoji,
    Map<String, int> previousCounts,
    Set<String> previousMine,
  ) async {
    try {
      final api = ref.read(apiServiceProvider);
      final response = await api.toggleReaction(postId, emoji);
      if (!mounted) return;
      final updatedCounts = response['reactions'] as Map<String, dynamic>?;
      final updatedMine = response['my_reactions'] as List<dynamic>?;
      
      if (updatedCounts != null) {
        setState(() {
          _reactionCountsByPost[postId] = updatedCounts
              .map((key, value) => MapEntry(key, value as int));
        });
      }
      if (updatedMine != null) {
        setState(() {
          _myReactionsByPost[postId] =
              updatedMine.map((item) => item.toString()).toSet();
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _reactionCountsByPost[postId] = Map<String, int>.from(previousCounts);
        _myReactionsByPost[postId] = Set<String>.from(previousMine);
      });
    }
  }

  Widget _buildAvatar(Post post) {
    final avatarUrl = post.author?.avatarUrl;
    final hasAvatar = avatarUrl != null && avatarUrl.trim().isNotEmpty;
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: AppTheme.brightNavy.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
      ),
      child: !hasAvatar
          ? Center(
              child: Text(
                _initialForName(post.author?.displayName),
                style: GoogleFonts.inter(
                  color: AppTheme.brightNavy,
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: SignedMediaImage(
                url: avatarUrl!,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
              ),
            ),
    );
  }

  Widget _buildCompactAvatar(Post post) {
    final avatarUrl = post.author?.avatarUrl;
    final hasAvatar = avatarUrl != null && avatarUrl.trim().isNotEmpty;
    return Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(
        color: AppTheme.brightNavy.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: !hasAvatar
          ? Center(
              child: Text(
                _initialForName(post.author?.displayName),
                style: GoogleFonts.inter(
                  color: AppTheme.brightNavy,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          : ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SignedMediaImage(
                url: avatarUrl!,
                width: 36,
                height: 36,
                fit: BoxFit.cover,
              ),
            ),
    );
  }

  String _initialForName(String? name) {
    final trimmed = name?.trim() ?? '';
    if (trimmed.isEmpty) return 'S';
    return trimmed.characters.first.toUpperCase();
  }

  Future<void> _sharePost(Post post) async {
    final handle = post.author?.handle ?? 'sojorn';
    final shareUrl = post.hasVideoContent == true
        ? AppRoutes.getQuipUrl(post.id) 
        : AppRoutes.getPostUrl(post.id);

    
    final text = '${post.body}\n\n$shareUrl\n\n— @$handle on Sojorn';


    try {
      await Share.share(text);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Unable to share right now.')),
        );
      }
    }
  }
}

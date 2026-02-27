// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import '../../routes/app_routes.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/settings_provider.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../widgets/reactions/anchored_reaction_popup.dart';
import '../../widgets/reactions/reactions_display.dart';
import '../../models/post.dart';
import '../../models/thread_node.dart';
import '../../providers/api_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/media/sojorn_avatar.dart';
import '../compose/compose_screen.dart';
import '../../services/analytics_service.dart';
import '../../services/notification_service.dart';
import '../../widgets/post/post_body.dart';
import '../../widgets/post/post_link_preview.dart';
import '../../widgets/post/post_view_mode.dart';
import '../../widgets/post/post_media.dart';
import '../home/full_screen_shell.dart';
import '../../widgets/desktop/desktop_slide_panel.dart';
import 'package:share_plus/share_plus.dart';

enum ChainView { thread, map }

class ThreadedConversationScreen extends ConsumerStatefulWidget {
  final String rootPostId;
  final Post? rootPost;

  const ThreadedConversationScreen({
    super.key,
    required this.rootPostId,
    this.rootPost,
  });

  @override
  ConsumerState<ThreadedConversationScreen> createState() =>
      _ThreadedConversationScreenState();
}

class _ThreadedConversationScreenState
    extends ConsumerState<ThreadedConversationScreen>
    with TickerProviderStateMixin {
  // ── Core navigation state ──────────────────────────────────────────────
  late String _currentPostId;
  FocusContext? _focusContext;
  ThreadNode? _tree;
  ChainView _view = ChainView.thread;
  final Set<String> _explored = {};
  bool _isLoading = true;
  String? _error;
  bool _showAllReplies = false;

  // ── Reaction / interaction state (carried over) ────────────────────────
  final Map<String, Map<String, int>> _reactionCountsByPost = {};
  final Map<String, Set<String>> _myReactionsByPost = {};
  final Map<String, Map<String, List<String>>> _reactionUsersByPost = {};
  final Map<String, bool> _savedByPost = {};
  final Set<String> _nsfwRevealed = {};
  int _maxDepthReached = 0;

  // ── Animation ──────────────────────────────────────────────────────────
  late AnimationController _fadeController;
  final ScrollController _breadcrumbScrollCtrl = ScrollController();

  // ── Computed helpers ───────────────────────────────────────────────────
  int get _currentDepth {
    if (_tree == null) return 0;
    final node = _tree!.findNode(_currentPostId);
    return node?.depth ?? 0;
  }

  bool _shouldBlurPost(Post post) {
    if (!post.isNsfw || _nsfwRevealed.contains(post.id)) return false;
    final settings = ref.read(settingsProvider);
    if (!(settings.user?.nsfwEnabled ?? false)) return true;
    return settings.user?.nsfwBlurEnabled ?? true;
  }

  // ── Lifecycle ──────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _currentPostId = widget.rootPostId;
    _explored.add(_currentPostId);
    NotificationService.instance.activePostId = widget.rootPostId;

    _fadeController = AnimationController(
      duration: const Duration(milliseconds: 200),
      reverseDuration: const Duration(milliseconds: 150),
      vsync: this,
    );

    if (widget.rootPost != null) {
      _focusContext = FocusContext(
        targetPost: widget.rootPost!,
        children: const [],
      );
      _seedReactionState(_focusContext!);
    }

    _loadInitialData();
    AnalyticsService.instance.event('chain_entered');
  }

  @override
  void dispose() {
    AnalyticsService.instance.event('chain_max_depth', value: '$_maxDepthReached');
    AnalyticsService.instance.event('chain_exit', value: '$_currentDepth');
    NotificationService.instance.activePostId = null;
    _fadeController.dispose();
    _breadcrumbScrollCtrl.dispose();
    super.dispose();
  }

  // ── Data loading ───────────────────────────────────────────────────────

  Future<void> _loadInitialData() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final api = ref.read(apiServiceProvider);
      // Load focus-context and full chain tree in parallel
      final results = await Future.wait([
        api.getPostFocusContext(_currentPostId),
        api.getPostChain(widget.rootPostId).catchError((_) => <Post>[]),
      ]);

      if (!mounted) return;
      final fc = results[0] as FocusContext;
      final chainPosts = results[1] as List<Post>;

      setState(() {
        _focusContext = fc;
        if (chainPosts.isNotEmpty) {
          try {
            _tree = ThreadNode.buildTree(chainPosts);
          } catch (_) {
            _tree = null;
          }
        }
        _isLoading = false;
      });

      _seedReactionState(fc);
      _fadeController.forward(from: 0);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _navigateToNode(String postId) async {
    if (postId == _currentPostId) return;

    // Fade out
    await _fadeController.reverse();

    if (!mounted) return;
    final oldDepth = _currentDepth;
    setState(() {
      _currentPostId = postId;
      _explored.add(postId);
      _isLoading = true;
      _showAllReplies = false;
    });
    final newDepth = _currentDepth;
    if (newDepth > _maxDepthReached) _maxDepthReached = newDepth;
    if (newDepth > oldDepth) {
      AnalyticsService.instance.event('chain_reply_tapped', value: '$newDepth');
    } else {
      AnalyticsService.instance.event('chain_parent_tapped', value: '$newDepth');
    }

    try {
      final api = ref.read(apiServiceProvider);
      final fc = await api.getPostFocusContext(postId);
      if (!mounted) return;
      setState(() {
        _focusContext = fc;
        _isLoading = false;
      });
      _seedReactionState(fc);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }

    // Fade in
    if (mounted) _fadeController.forward();

    // Auto-scroll breadcrumbs to end
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_breadcrumbScrollCtrl.hasClients) {
        _breadcrumbScrollCtrl.animateTo(
          _breadcrumbScrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _goHome() => _navigateToNode(_tree?.post.id ?? widget.rootPostId);

  // ── Build ──────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    final header = _buildHeader();

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
          title: header,
          centerTitle: false,
        ),
        body: _buildBody(),
      );
    }

    return FullScreenShell(
      title: header,
      body: _buildBody(),
    );
  }

  Widget _buildHeader() {
    final depth = _currentDepth;
    final total = _tree?.totalCount ?? 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Home button
        GestureDetector(
          onTap: depth > 0 ? _goHome : null,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: depth > 0
                  ? AppTheme.brightNavy.withValues(alpha: 0.1)
                  : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: depth > 0
                    ? AppTheme.brightNavy.withValues(alpha: 0.25)
                    : AppTheme.textTertiary.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.home_outlined,
                    size: 16,
                    color: depth > 0
                        ? AppTheme.brightNavy
                        : AppTheme.textTertiary),
                if (depth > 0) ...[
                  const SizedBox(width: 4),
                  Text('Root',
                      style: GoogleFonts.inter(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.brightNavy)),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text('Chain',
            style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: AppTheme.textPrimary)),
        if (depth > 0) ...[
          const SizedBox(width: 8),
          _buildDepthPill(depth, total),
        ],
        const Spacer(),
        // View toggle
        _buildViewToggle(),
      ],
    );
  }

  Widget _buildDepthPill(int depth, int total) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: AppTheme.isDark
                ? SojornColors.darkBorder
                : AppTheme.egyptianBlue.withValues(alpha: 0.15)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.arrow_downward, size: 12, color: AppTheme.textTertiary),
          const SizedBox(width: 4),
          Text(
            '$depth deep${total > 0 ? ' · $total total' : ''}',
            style: GoogleFonts.inter(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: AppTheme.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildViewToggle() {
    return Container(
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
            color: AppTheme.isDark
                ? SojornColors.darkBorder
                : AppTheme.egyptianBlue.withValues(alpha: 0.12)),
      ),
      padding: const EdgeInsets.all(2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _viewToggleButton(ChainView.thread, Icons.view_agenda_outlined),
          _viewToggleButton(ChainView.map, Icons.account_tree_outlined),
        ],
      ),
    );
  }

  Widget _viewToggleButton(ChainView view, IconData icon) {
    final isActive = _view == view;
    return GestureDetector(
      onTap: () => setState(() => _view = view),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isActive
              ? AppTheme.brightNavy.withValues(alpha: 0.1)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(icon,
            size: 16,
            color: isActive ? AppTheme.brightNavy : AppTheme.textTertiary),
      ),
    );
  }

  // ── Body ───────────────────────────────────────────────────────────────

  Widget _buildBody() {
    if (_isLoading && _focusContext == null) return _buildLoadingState();
    if (_error != null && _focusContext == null) return _buildErrorState();
    if (_focusContext == null) return _buildEmptyState();

    return FadeTransition(
      opacity: _fadeController,
      child: _view == ChainView.thread ? _buildThreadView() : _buildMapView(),
    );
  }

  Widget _buildLoadingState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: AppTheme.brightNavy),
          const SizedBox(height: 16),
          Text('Loading chain...',
              style: GoogleFonts.inter(
                  color: AppTheme.textSecondary, fontSize: 16)),
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
            Text('Failed to load chain',
                style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(_error!,
                style: GoogleFonts.inter(
                    color: AppTheme.textSecondary, fontSize: 14),
                textAlign: TextAlign.center),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _loadInitialData,
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
      child: Text('Chain not found',
          style:
              GoogleFonts.inter(color: AppTheme.textSecondary, fontSize: 16)),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // THREAD VIEW
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildThreadView() {
    final fc = _focusContext!;
    final children = fc.children;

    return RefreshIndicator(
      onRefresh: _loadInitialData,
      color: AppTheme.brightNavy,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Breadcrumb trail
            if (_currentDepth > 0) _buildBreadcrumbs(),

            // Parent post card (above current post)
            if (fc.parentPost != null)
              _buildParentCard(fc.parentPost!),

            // Stage: current post
            _buildStageZone(fc.targetPost),
            const SizedBox(height: 20),

            // Children grid or end-of-branch
            if (children.isNotEmpty)
              _buildChildrenGrid(children)
            else
              _buildEndOfBranch(),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // ── Breadcrumb trail ───────────────────────────────────────────────────

  Widget _buildBreadcrumbs() {
    if (_tree == null) return const SizedBox.shrink();
    final path = _tree!.pathTo(_currentPostId);
    if (path.length <= 1) return const SizedBox.shrink();

    return Container(
      height: 48,
      padding: const EdgeInsets.symmetric(vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: AppTheme.isDark
                ? SojornColors.darkBorder
                : AppTheme.egyptianBlue.withValues(alpha: 0.08),
          ),
        ),
        color: AppTheme.isDark
            ? SojornColors.darkCardSurface.withValues(alpha: 0.5)
            : AppTheme.navyBlue.withValues(alpha: 0.02),
      ),
      child: ListView.separated(
        controller: _breadcrumbScrollCtrl,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: path.length,
        separatorBuilder: (_, __) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Icon(Icons.chevron_right,
              size: 14, color: AppTheme.textTertiary),
        ),
        itemBuilder: (_, i) {
          final node = path[i];
          final isCurrent = node.post.id == _currentPostId;
          final isRoot = i == 0;

          return GestureDetector(
            onTap: isCurrent ? null : () => _navigateToNode(node.post.id),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isCurrent
                    ? AppTheme.brightNavy.withValues(alpha: 0.1)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(8),
                border: isCurrent
                    ? Border.all(
                        color: AppTheme.brightNavy.withValues(alpha: 0.25))
                    : null,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (isRoot)
                    Icon(Icons.home,
                        size: 14,
                        color: isCurrent
                            ? AppTheme.brightNavy
                            : AppTheme.textTertiary)
                  else
                    SojornAvatar(
                      displayName:
                          node.post.author?.displayName ?? 'Anonymous',
                      avatarUrl: node.post.author?.avatarUrl,
                      size: 18,
                    ),
                  const SizedBox(width: 5),
                  Text(
                    isRoot
                        ? 'Root'
                        : (node.post.author?.displayName ?? 'Anon')
                            .split(' ')
                            .first,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                      color: isCurrent
                          ? AppTheme.brightNavy
                          : AppTheme.textTertiary,
                    ),
                  ),
                  if (node.children.length > 1 && !isCurrent) ...[
                    const SizedBox(width: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: AppTheme.cardSurface,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text('+${node.children.length - 1}',
                          style: GoogleFonts.inter(
                              fontSize: 9,
                              fontWeight: FontWeight.w600,
                              color: AppTheme.textTertiary)),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Parent card (above current post) ───────────────────────────────────

  Widget _buildParentCard(Post parent) {
    final parentName = parent.author?.displayName ?? 'Anonymous';
    final parentReactions = _reactionCountsFor(parent);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          GestureDetector(
            onTap: () => _navigateToNode(parent.id),
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
              decoration: BoxDecoration(
                color: AppTheme.isDark
                    ? const Color(0xFF1A1B2E)
                    : const Color(0xFFF0F0F8),
                borderRadius: BorderRadius.circular(SojornRadii.card),
                border: Border.all(
                  color: AppTheme.isDark
                      ? const Color(0xFF2A2B45)
                      : const Color(0xFFE0E0F0),
                ),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SojornAvatar(
                    displayName: parentName,
                    avatarUrl: parent.author?.avatarUrl,
                    size: 34,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(parentName,
                                style: GoogleFonts.inter(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w700,
                                    color: AppTheme.textPrimary)),
                            const SizedBox(width: 6),
                            if (parent.author?.handle != null)
                              Text('@${parent.author!.handle}',
                                  style: GoogleFonts.inter(
                                      fontSize: 11,
                                      color: AppTheme.textTertiary)),
                            const SizedBox(width: 4),
                            Text('·',
                                style: TextStyle(
                                    color: AppTheme.textTertiary)),
                            const SizedBox(width: 4),
                            Text(timeago.format(parent.createdAt),
                                style: GoogleFonts.inter(
                                    fontSize: 11,
                                    color: AppTheme.textTertiary)),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(parent.body,
                            style: GoogleFonts.inter(
                                fontSize: 15,
                                color: AppTheme.textPrimary,
                                height: 1.45),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis),
                        if (parentReactions.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          ReactionsDisplay(
                            reactionCounts: parentReactions,
                            myReactions: _myReactionsFor(parent),
                            onToggleReaction: (emoji) =>
                                _toggleReaction(parent.id, emoji),
                            onAddReaction: (pos) =>
                                _openReactionPicker(parent.id, pos),
                            mode: ReactionsDisplayMode.compact,
                            padding: EdgeInsets.zero,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // "PARENT" badge
          Positioned(
            top: -1,
            right: 16,
            child: Container(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
              decoration: BoxDecoration(
                color: AppTheme.brightNavy,
                borderRadius: const BorderRadius.only(
                  bottomLeft: Radius.circular(10),
                  bottomRight: Radius.circular(10),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.arrow_upward,
                      size: 10, color: SojornColors.basicWhite),
                  const SizedBox(width: 4),
                  Text('PARENT',
                      style: GoogleFonts.inter(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: SojornColors.basicWhite,
                          letterSpacing: 0.3)),
                ],
              ),
            ),
          ),
          // Connecting line down to current post
          Positioned(
            bottom: -17,
            left: 32,
            child: Container(
              width: 2,
              height: 16,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppTheme.isDark
                        ? SojornColors.darkBorder
                        : const Color(0xFFE0E0F0),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Stage zone (current post) ──────────────────────────────────────────

  Widget _buildStageZone(Post focalPost) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(SojornRadii.xl),
        border: Border.all(
          color: AppTheme.brightNavy.withValues(alpha: 0.3),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: AppTheme.brightNavy.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Author header
            _buildStageHeader(focalPost),
            const SizedBox(height: 14),

            // Content (with NSFW handling)
            if (_shouldBlurPost(focalPost)) ...[
              ClipRect(
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: _buildStageContent(focalPost),
                ),
              ),
              if (focalPost.imageUrl != null ||
                  focalPost.videoUrl != null ||
                  focalPost.thumbnailUrl != null) ...[
                const SizedBox(height: 16),
                ClipRect(
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
                    child:
                        PostMedia(post: focalPost, mode: PostViewMode.detail),
                  ),
                ),
              ],
              const SizedBox(height: 12),
              GestureDetector(
                onTap: () =>
                    setState(() => _nsfwRevealed.add(focalPost.id)),
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  decoration: BoxDecoration(
                    color: AppTheme.nsfwWarningBg,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppTheme.nsfwWarningBorder),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.visibility_off,
                          size: 18, color: AppTheme.nsfwWarningIcon),
                      const SizedBox(width: 8),
                      Text('Sensitive Content — Tap to reveal',
                          style: TextStyle(
                              color: AppTheme.nsfwWarningText,
                              fontWeight: FontWeight.w600,
                              fontSize: 13)),
                    ],
                  ),
                ),
              ),
            ] else ...[
              _buildStageContent(focalPost),
              if (focalPost.imageUrl != null ||
                  focalPost.videoUrl != null ||
                  focalPost.thumbnailUrl != null) ...[
                const SizedBox(height: 16),
                PostMedia(post: focalPost, mode: PostViewMode.detail),
              ],
            ],

            const SizedBox(height: 18),
            _buildStageActions(focalPost),
          ],
        ),
      ),
    );
  }

  Widget _buildStageHeader(Post post) {
    return Row(
      children: [
        SojornAvatar(
          displayName: post.author?.displayName ?? 'Anonymous',
          avatarUrl: post.author?.avatarUrl,
          size: 44,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                post.author?.displayName ?? 'Anonymous',
                style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 2),
              Text(
                '@${post.author?.handle ?? 'anonymous'}',
                style: GoogleFonts.inter(
                    color: AppTheme.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500),
              ),
              const SizedBox(height: 2),
              Row(
                children: [
                  Icon(Icons.schedule_outlined,
                      size: 11,
                      color: AppTheme.textTertiary),
                  const SizedBox(width: 3),
                  Text(timeago.format(post.createdAt),
                      style: GoogleFonts.inter(
                          color: AppTheme.textTertiary,
                          fontSize: 11)),
                  const SizedBox(width: 8),
                  Icon(
                    post.visibility == 'followers'
                        ? Icons.people_outline
                        : Icons.public,
                    size: 11,
                    color: AppTheme.textTertiary,
                  ),
                ],
              ),
            ],
          ),
        ),
        if (_focusContext!.children.isNotEmpty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppTheme.egyptianBlue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.chat_bubble_outline,
                    size: 14, color: AppTheme.egyptianBlue),
                const SizedBox(width: 5),
                Text(
                  '${_focusContext!.children.length}',
                  style: GoogleFonts.inter(
                      color: AppTheme.egyptianBlue,
                      fontSize: 12,
                      fontWeight: FontWeight.w600),
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
        if (post.hasLinkPreview) ...[
          const SizedBox(height: 8),
          PostLinkPreview(post: post, mode: PostViewMode.detail),
        ],
      ],
    );
  }

  Widget _buildStageActions(Post post) {
    final isSaved = _savedByPost[post.id] ?? (post.isSaved ?? false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReactionsDisplay(
          reactionCounts: _reactionCountsFor(post),
          myReactions: _myReactionsFor(post),
          reactionUsers: _reactionUsersFor(post),
          onToggleReaction: (emoji) => _toggleReaction(post.id, emoji),
          onAddReaction: (pos) => _openReactionPicker(post.id, pos),
          mode: ReactionsDisplayMode.full,
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: post.allowChain
                    ? () => _openReplyComposer(post)
                    : null,
                icon: const Icon(Icons.reply, size: 18),
                label: const Text('Reply'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.navyBlue.withValues(alpha: 0.05),
                  foregroundColor: AppTheme.navyBlue,
                  elevation: 0,
                  shadowColor: SojornColors.transparent,
                  minimumSize: const Size(0, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton(
              onPressed: () => _sharePost(post),
              icon: Icon(Icons.share_outlined, color: AppTheme.textSecondary),
              style: IconButton.styleFrom(
                backgroundColor: AppTheme.navyBlue.withValues(alpha: 0.05),
                minimumSize: const Size(42, 42),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              onPressed: () => _toggleSave(post),
              icon: Icon(
                isSaved ? Icons.bookmark : Icons.bookmark_border,
                color: isSaved ? AppTheme.brightNavy : AppTheme.textSecondary,
              ),
              style: IconButton.styleFrom(
                backgroundColor: AppTheme.navyBlue.withValues(alpha: 0.05),
                minimumSize: const Size(42, 42),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // ── Children grid ──────────────────────────────────────────────────────

  /// Score a reply by total reactions + descendants for ranking
  int _replyScore(Post post) {
    final reactions = _reactionCountsFor(post);
    final reactionTotal = reactions.values.fold(0, (a, b) => a + b);
    final descendants = _tree?.findNode(post.id)?.totalDescendants ?? 0;
    return reactionTotal + descendants;
  }

  Widget _buildChildrenGrid(List<Post> children) {
    final unexploredCount =
        children.where((c) => !_explored.contains(c.id)).length;

    // Sort by engagement score (reactions + descendants), descending
    final sorted = List<Post>.from(children)
      ..sort((a, b) => _replyScore(b).compareTo(_replyScore(a)));

    const maxVisible = 4;
    final hasMore = sorted.length > maxVisible && !_showAllReplies;
    final visible = hasMore ? sorted.sublist(0, maxVisible) : sorted;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: AppTheme.brightNavy.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: AppTheme.brightNavy.withValues(alpha: 0.2)),
                ),
                child: Center(
                  child: Icon(Icons.double_arrow,
                      size: 12, color: AppTheme.brightNavy),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${children.length} ${children.length == 1 ? 'Reply' : 'Replies'}',
                style: GoogleFonts.inter(
                    color: AppTheme.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              if (unexploredCount > 0)
                Text('$unexploredCount new',
                    style: GoogleFonts.inter(
                        fontSize: 11, color: AppTheme.textTertiary)),
            ],
          ),
          const SizedBox(height: 12),
          // Grid
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: visible.length == 1 ? 1 : 2,
              crossAxisSpacing: 10,
              mainAxisSpacing: 10,
              childAspectRatio: visible.length == 1 ? 2.5 : 0.85,
            ),
            itemCount: visible.length,
            itemBuilder: (_, i) => _buildReplyCard(visible[i]),
          ),
          // Show more button
          if (hasMore) ...[
            const SizedBox(height: 12),
            GestureDetector(
              onTap: () => setState(() => _showAllReplies = true),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: AppTheme.brightNavy.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(SojornRadii.lg),
                  border: Border.all(
                    color: AppTheme.brightNavy.withValues(alpha: 0.15),
                  ),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.expand_more,
                        size: 16, color: AppTheme.brightNavy),
                    const SizedBox(width: 6),
                    Text(
                      'Show ${sorted.length - maxVisible} more ${sorted.length - maxVisible == 1 ? 'reply' : 'replies'}',
                      style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.brightNavy),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReplyCard(Post post) {
    final isExplored = _explored.contains(post.id);
    final treeNode = _tree?.findNode(post.id);
    final descendants = treeNode?.totalDescendants ?? 0;
    final subDepth = treeNode != null
        ? treeNode.maxTreeDepth - treeNode.depth
        : 0;

    // Author-based color for left border
    final authorName = post.author?.displayName ?? 'Anonymous';
    final colorIndex = authorName.codeUnits.fold(0, (a, b) => a + b) % 8;
    final borderColors = [
      const Color(0xFF6366F1), const Color(0xFFE85D75),
      const Color(0xFF10B981), const Color(0xFFF59E0B),
      const Color(0xFF8B5CF6), const Color(0xFFEC4899),
      const Color(0xFF14B8A6), const Color(0xFFF97316),
    ];
    final borderColor = borderColors[colorIndex];

    final subtleBorder = AppTheme.isDark
        ? SojornColors.darkBorder
        : AppTheme.egyptianBlue.withValues(alpha: 0.1);

    return GestureDetector(
      onTap: () => _navigateToNode(post.id),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(SojornRadii.lg),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            border: Border(
              left: BorderSide(color: borderColor, width: 3),
              top: BorderSide(color: subtleBorder),
              right: BorderSide(color: subtleBorder),
              bottom: BorderSide(color: subtleBorder),
            ),
          ),
          child: Stack(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Author row
                Row(
                  children: [
                    SojornAvatar(
                      displayName: authorName,
                      avatarUrl: post.author?.avatarUrl,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(authorName,
                              style: GoogleFonts.inter(
                                  color: AppTheme.textPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis),
                          Text(timeago.format(post.createdAt),
                              style: GoogleFonts.inter(
                                  color: AppTheme.textTertiary,
                                  fontSize: 10)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Image/GIF thumbnail + text preview
                if (post.imageUrl != null && post.imageUrl!.isNotEmpty)
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(SojornRadii.sm),
                      child: SizedBox(
                        width: double.infinity,
                        child: _shouldBlurPost(post)
                            ? ImageFiltered(
                                imageFilter:
                                    ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                                child: Image.network(
                                  post.imageUrl!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, __, ___) =>
                                      const SizedBox.shrink(),
                                ),
                              )
                            : Image.network(
                                post.imageUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) =>
                                    const SizedBox.shrink(),
                              ),
                      ),
                    ),
                  )
                else
                  Expanded(
                    child: _shouldBlurPost(post)
                        ? GestureDetector(
                            onTap: () => setState(
                                () => _nsfwRevealed.add(post.id)),
                            child: ImageFiltered(
                              imageFilter:
                                  ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                              child: Text(post.body,
                                  style: GoogleFonts.inter(
                                      color: AppTheme.postContent,
                                      fontSize: 12,
                                      height: 1.4),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis),
                            ),
                          )
                        : Text(post.body,
                            style: GoogleFonts.inter(
                                color: AppTheme.postContent,
                                fontSize: 12,
                                height: 1.4),
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis),
                  ),
                const SizedBox(height: 8),
                // Bottom row: reactions + depth info
                Row(
                  children: [
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        physics: const NeverScrollableScrollPhysics(),
                        child: ReactionsDisplay(
                          reactionCounts: _reactionCountsFor(post),
                          myReactions: _myReactionsFor(post),
                          onToggleReaction: (emoji) =>
                              _toggleReaction(post.id, emoji),
                          onAddReaction: (pos) =>
                              _openReactionPicker(post.id, pos),
                          mode: ReactionsDisplayMode.compact,
                          padding: EdgeInsets.zero,
                        ),
                      ),
                    ),
                    if (descendants > 0)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.double_arrow,
                              size: 10, color: AppTheme.brightNavy),
                          const SizedBox(width: 3),
                          Text(
                            '$descendants${subDepth > 1 ? ' · ${subDepth}d' : ''}',
                            style: GoogleFonts.inter(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: AppTheme.brightNavy),
                          ),
                        ],
                      ),
                  ],
                ),
              ],
            ),
            // Unexplored blue dot
            if (!isExplored)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppTheme.brightNavy,
                  ),
                ),
              ),
          ],
        ),
      ),
      ),
    );
  }

  // ── End of branch ──────────────────────────────────────────────────────

  Widget _buildEndOfBranch() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 20),
      decoration: BoxDecoration(
        color: AppTheme.isDark
            ? SojornColors.darkCardSurface
            : AppTheme.navyBlue.withValues(alpha: 0.02),
        borderRadius: BorderRadius.circular(SojornRadii.card),
        border: Border.all(
          color: AppTheme.isDark
              ? SojornColors.darkBorder
              : AppTheme.egyptianBlue.withValues(alpha: 0.1),
          style: BorderStyle.solid,
        ),
      ),
      child: Column(
        children: [
          const Text('🍃', style: TextStyle(fontSize: 32)),
          const SizedBox(height: 10),
          Text('End of this branch',
              style: GoogleFonts.inter(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          Text('Be the first to continue the chain',
              style: GoogleFonts.inter(
                  color: AppTheme.textSecondary, fontSize: 13)),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: _focusContext?.targetPost.allowChain == true
                ? () => _openReplyComposer(_focusContext!.targetPost)
                : null,
            icon: const Icon(Icons.reply, size: 18),
            label: const Text('Reply'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.brightNavy,
              foregroundColor: SojornColors.basicWhite,
              elevation: 0,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // MAP VIEW
  // ═══════════════════════════════════════════════════════════════════════

  Widget _buildMapView() {
    if (_tree == null) return _buildLoadingState();

    final positions = _layoutTree(_tree!);
    final maxX = positions.values.map((o) => o.dx).reduce(math.max) + 60;
    final maxY = positions.values.map((o) => o.dy).reduce(math.max) + 60;

    return Column(
      children: [
        // Legend
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              Text('Conversation Map',
                  style: GoogleFonts.inter(
                      color: AppTheme.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              _legendDot(AppTheme.brightNavy, 'New'),
              const SizedBox(width: 12),
              _legendDot(AppTheme.textTertiary, 'Visited'),
            ],
          ),
        ),
        // Tree
        Expanded(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: AppTheme.isDark
                  ? SojornColors.darkCardSurface
                  : AppTheme.navyBlue.withValues(alpha: 0.02),
              borderRadius: BorderRadius.circular(SojornRadii.card),
              border: Border.all(
                color: AppTheme.isDark
                    ? SojornColors.darkBorder
                    : AppTheme.egyptianBlue.withValues(alpha: 0.1),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(SojornRadii.card),
              child: InteractiveViewer(
                boundaryMargin: const EdgeInsets.all(80),
                minScale: 0.3,
                maxScale: 2.5,
                child: GestureDetector(
                  onTapDown: (details) =>
                      _handleMapTap(details.localPosition, positions),
                  child: CustomPaint(
                    size: Size(maxX, maxY),
                    painter: _ChainTreePainter(
                      tree: _tree!,
                      positions: positions,
                      currentPostId: _currentPostId,
                      explored: _explored,
                      brandColor: AppTheme.brightNavy,
                      textColor: AppTheme.textPrimary,
                      lineColor: AppTheme.textTertiary.withValues(alpha: 0.25),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        // Preview card
        _buildMapPreviewCard(),
      ],
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(shape: BoxShape.circle, color: color)),
        const SizedBox(width: 4),
        Text(label,
            style: GoogleFonts.inter(
                fontSize: 10, color: AppTheme.textTertiary)),
      ],
    );
  }

  Map<String, Offset> _layoutTree(ThreadNode root) {
    final positions = <String, Offset>{};
    int leafCounter = 0;
    const hSpacing = 80.0;
    const vSpacing = 70.0;
    const startX = 40.0;
    const startY = 40.0;

    void layout(ThreadNode node) {
      if (node.children.isEmpty) {
        positions[node.post.id] =
            Offset(startX + leafCounter * hSpacing, startY + node.depth * vSpacing);
        leafCounter++;
      } else {
        for (final child in node.children) {
          layout(child);
        }
        final childPositions =
            node.children.map((c) => positions[c.post.id]!).toList();
        final avgX =
            childPositions.map((p) => p.dx).reduce((a, b) => a + b) /
                childPositions.length;
        positions[node.post.id] = Offset(avgX, startY + node.depth * vSpacing);
      }
    }

    layout(root);
    return positions;
  }

  void _handleMapTap(Offset tapPos, Map<String, Offset> positions) {
    const hitRadius = 20.0;
    for (final entry in positions.entries) {
      if ((tapPos - entry.value).distance <= hitRadius) {
        _navigateToNode(entry.key);
        return;
      }
    }
  }

  Widget _buildMapPreviewCard() {
    final node = _tree?.findNode(_currentPostId);
    if (node == null) return const SizedBox.shrink();
    final post = node.post;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppTheme.isDark
              ? SojornColors.darkBorder
              : AppTheme.egyptianBlue.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        children: [
          SojornAvatar(
            displayName: post.author?.displayName ?? 'Anonymous',
            avatarUrl: post.author?.avatarUrl,
            size: 28,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(post.author?.displayName ?? 'Anonymous',
                        style: GoogleFonts.inter(
                            color: AppTheme.textPrimary,
                            fontSize: 13,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(width: 6),
                    Text(timeago.format(post.createdAt),
                        style: GoogleFonts.inter(
                            color: AppTheme.textTertiary, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(post.body,
                    style: GoogleFonts.inter(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                        height: 1.3),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════════
  // REACTION / INTERACTION LOGIC (carried over)
  // ═══════════════════════════════════════════════════════════════════════

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
          post.id, () => Map<String, int>.from(post.reactions!));
    }
    if (post.myReactions != null) {
      _myReactionsByPost.putIfAbsent(
          post.id, () => post.myReactions!.toSet());
    }
    if (post.reactionUsers != null) {
      _reactionUsersByPost.putIfAbsent(
          post.id, () => Map<String, List<String>>.from(post.reactionUsers!));
    }
  }

  Map<String, int> _reactionCountsFor(Post post) =>
      _reactionCountsByPost[post.id] ?? post.reactions ?? {};

  Set<String> _myReactionsFor(Post post) =>
      _myReactionsByPost[post.id] ?? post.myReactions?.toSet() ?? <String>{};

  Map<String, List<String>>? _reactionUsersFor(Post post) =>
      _reactionUsersByPost[post.id] ?? post.reactionUsers;

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

  Future<void> _persistReaction(String postId, String emoji,
      Map<String, int> previousCounts, Set<String> previousMine) async {
    try {
      final api = ref.read(apiServiceProvider);
      final response = await api.toggleReaction(postId, emoji);
      if (!mounted) return;
      final updatedCounts = response['reactions'] as Map<String, dynamic>?;
      final updatedMine = response['my_reactions'] as List<dynamic>?;
      if (updatedCounts != null) {
        setState(() {
          _reactionCountsByPost[postId] =
              updatedCounts.map((key, value) => MapEntry(key, value as int));
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

  Future<void> _openReactionPicker(String postId, Offset tapPosition) async {
    showAnchoredReactionPicker(
      context: context,
      tapPosition: tapPosition,
      myReactions: _myReactionsByPost[postId] ?? <String>{},
      reactionCounts: _reactionCountsByPost[postId],
      onReaction: (emoji) => _toggleReaction(postId, emoji),
    );
  }

  Future<void> _toggleSave(Post post) async {
    final current = _savedByPost[post.id] ?? (post.isSaved ?? false);
    setState(() => _savedByPost[post.id] = !current);
    try {
      final api = ref.read(apiServiceProvider);
      if (!current) {
        await api.savePost(post.id);
      } else {
        await api.unsavePost(post.id);
      }
    } catch (_) {
      if (mounted) setState(() => _savedByPost[post.id] = current);
    }
  }

  Future<void> _openReplyComposer(Post post) async {
    final isDesktop = MediaQuery.of(context).size.width >= 900;
    if (isDesktop) {
      openDesktopSlidePanel(context,
          width: 520, child: ComposeScreen(chainParentPost: post));
      await Future.delayed(const Duration(milliseconds: 300));
      _loadInitialData();
    } else {
      final result = await Navigator.of(context).push<bool>(
        MaterialPageRoute(
            builder: (context) => ComposeScreen(chainParentPost: post)),
      );
      FocusManager.instance.primaryFocus?.unfocus();
      if (result == true) _loadInitialData();
    }
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
            const SnackBar(content: Text('Unable to share right now.')));
      }
    }
  }
}

// ═════════════════════════════════════════════════════════════════════════
// CUSTOM PAINTER — Conversation tree for map view
// ═════════════════════════════════════════════════════════════════════════

class _ChainTreePainter extends CustomPainter {
  final ThreadNode tree;
  final Map<String, Offset> positions;
  final String currentPostId;
  final Set<String> explored;
  final Color brandColor;
  final Color textColor;
  final Color lineColor;

  _ChainTreePainter({
    required this.tree,
    required this.positions,
    required this.currentPostId,
    required this.explored,
    required this.brandColor,
    required this.textColor,
    required this.lineColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = lineColor
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Draw connections
    _drawConnections(canvas, tree, linePaint);

    // Draw nodes
    for (final node in tree.allNodes) {
      final pos = positions[node.post.id];
      if (pos == null) continue;
      _drawNode(canvas, node, pos);
    }
  }

  void _drawConnections(Canvas canvas, ThreadNode node, Paint paint) {
    final parentPos = positions[node.post.id];
    if (parentPos == null) return;

    for (final child in node.children) {
      final childPos = positions[child.post.id];
      if (childPos == null) continue;

      final path = Path()
        ..moveTo(parentPos.dx, parentPos.dy + 14)
        ..cubicTo(
          parentPos.dx,
          (parentPos.dy + childPos.dy) / 2,
          childPos.dx,
          (parentPos.dy + childPos.dy) / 2,
          childPos.dx,
          childPos.dy - 14,
        );

      final connectionPaint = Paint()
        ..color = lineColor
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke;
      canvas.drawPath(path, connectionPaint);

      _drawConnections(canvas, child, paint);
    }
  }

  void _drawNode(Canvas canvas, ThreadNode node, Offset pos) {
    final isCurrent = node.post.id == currentPostId;
    final isExplored = explored.contains(node.post.id);
    final radius = isCurrent ? 16.0 : 12.0;

    // Author-based color
    final name = node.post.author?.displayName ?? 'A';
    final colorIndex = name.codeUnits.fold(0, (a, b) => a + b) % 8;
    final colors = [
      const Color(0xFF6366F1), const Color(0xFFE85D75),
      const Color(0xFF10B981), const Color(0xFFF59E0B),
      const Color(0xFF8B5CF6), const Color(0xFFEC4899),
      const Color(0xFF14B8A6), const Color(0xFFF97316),
    ];
    final nodeColor = colors[colorIndex];

    // Fill
    final fillPaint = Paint()
      ..color = isCurrent
          ? brandColor
          : isExplored
              ? nodeColor.withValues(alpha: 0.3)
              : nodeColor.withValues(alpha: 0.15);
    canvas.drawCircle(pos, radius, fillPaint);

    // Stroke
    final strokePaint = Paint()
      ..color = isCurrent
          ? brandColor
          : isExplored
              ? nodeColor
              : nodeColor.withValues(alpha: 0.5)
      ..strokeWidth = isCurrent ? 2.5 : 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(pos, radius, strokePaint);

    // Initials text
    final initial = name.characters.first.toUpperCase();
    final textPainter = TextPainter(
      text: TextSpan(
        text: initial,
        style: TextStyle(
          color: isCurrent ? Colors.white : nodeColor,
          fontSize: isCurrent ? 10 : 8,
          fontWeight: FontWeight.w700,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
        canvas,
        Offset(pos.dx - textPainter.width / 2,
            pos.dy - textPainter.height / 2));

    // Unexplored blue dot
    if (!isExplored && node.post.id != tree.post.id) {
      final dotPaint = Paint()..color = brandColor;
      canvas.drawCircle(
          Offset(pos.dx + radius * 0.7, pos.dy - radius * 0.7), 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ChainTreePainter old) =>
      old.currentPostId != currentPostId || old.explored.length != explored.length;
}

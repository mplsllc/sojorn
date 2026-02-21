// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/cluster.dart';
import '../../models/post.dart';
import '../../providers/api_provider.dart';
import '../../theme/tokens.dart';
import '../../theme/app_theme.dart';
import '../../widgets/sojorn_post_card.dart';
import '../../widgets/post/post_view_mode.dart';

/// PublicClusterScreen — "Open Door" aesthetic for geo-fenced public clusters.
/// Standard feed layout with beacon integration, light/airy feel.
class PublicClusterScreen extends ConsumerStatefulWidget {
  final Cluster cluster;
  const PublicClusterScreen({super.key, required this.cluster});

  @override
  ConsumerState<PublicClusterScreen> createState() => _PublicClusterScreenState();
}

class _PublicClusterScreenState extends ConsumerState<PublicClusterScreen> {
  List<Post> _posts = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPosts();
  }

  Future<void> _loadPosts() async {
    setState(() => _isLoading = true);
    try {
      final api = ref.read(apiServiceProvider);
      final raw = await api.callGoApi('/groups/${widget.cluster.id}/feed', method: 'GET');
      final items = (raw['posts'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      final posts = items.map((j) => Post.fromJson(j)).toList();
      if (mounted) setState(() { _posts = posts; _isLoading = false; });
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      body: CustomScrollView(
        slivers: [
          // ── Cluster header ────────────────────────────────────────
          SliverAppBar(
            expandedHeight: 180,
            pinned: true,
            backgroundColor: AppTheme.navyBlue,
            foregroundColor: SojornColors.basicWhite,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(
                widget.cluster.name,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
              ),
              background: Container(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      AppTheme.brightNavy,
                      AppTheme.navyBlue,
                    ],
                  ),
                ),
                child: SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 40, 16, 50),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: SojornColors.basicWhite.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.public, size: 12, color: SojornColors.basicWhite),
                                  const SizedBox(width: 4),
                                  Text(
                                    'PUBLIC CLUSTER',
                                    style: TextStyle(
                                      color: SojornColors.basicWhite.withValues(alpha: 0.9),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.8,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                            Icon(Icons.people, size: 14, color: SojornColors.basicWhite.withValues(alpha: 0.7)),
                            const SizedBox(width: 4),
                            Text(
                              '${widget.cluster.memberCount}',
                              style: TextStyle(
                                color: SojornColors.basicWhite.withValues(alpha: 0.7),
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        if (widget.cluster.description.isNotEmpty) ...[
                          const Spacer(),
                          Text(
                            widget.cluster.description,
                            style: TextStyle(
                              color: SojornColors.basicWhite.withValues(alpha: 0.7),
                              fontSize: 13,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Quick actions bar ─────────────────────────────────────
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  _QuickAction(icon: Icons.map, label: 'Map View', onTap: () {}),
                  const SizedBox(width: 8),
                  _QuickAction(icon: Icons.warning_amber, label: 'Alerts', onTap: () {}),
                  const SizedBox(width: 8),
                  _QuickAction(icon: Icons.info_outline, label: 'Resources', onTap: () {}),
                ],
              ),
            ),
          ),

          // ── Feed ──────────────────────────────────────────────────
          if (_isLoading)
            const SliverFillRemaining(
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_posts.isEmpty)
            SliverFillRemaining(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.location_on, size: 48, color: AppTheme.navyBlue.withValues(alpha: 0.3)),
                    const SizedBox(height: 12),
                    Text(
                      'No activity in this cluster yet',
                      style: TextStyle(color: AppTheme.navyBlue.withValues(alpha: 0.5), fontSize: 14),
                    ),
                  ],
                ),
              ),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: sojornPostCard(
                    post: _posts[index],
                    mode: PostViewMode.feed,
                  ),
                ),
                childCount: _posts.length,
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 40)),
        ],
      ),
    );
  }
}

class _QuickAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _QuickAction({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: AppTheme.brightNavy.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppTheme.brightNavy.withValues(alpha: 0.12)),
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: AppTheme.brightNavy),
              const SizedBox(height: 4),
              Text(label, style: TextStyle(fontSize: 11, color: AppTheme.navyBlue.withValues(alpha: 0.7), fontWeight: FontWeight.w500)),
            ],
          ),
        ),
      ),
    );
  }
}

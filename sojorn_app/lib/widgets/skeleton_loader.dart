import 'package:flutter/material.dart';
import '../theme/app_theme.dart';

/// Shimmer-animated skeleton placeholder for loading states.
/// Use [SkeletonPostCard], [SkeletonGroupCard], etc. for specific shapes.
class SkeletonBox extends StatefulWidget {
  final double width;
  final double height;
  final double borderRadius;

  const SkeletonBox({
    super.key,
    required this.width,
    required this.height,
    this.borderRadius = 8,
  });

  @override
  State<SkeletonBox> createState() => _SkeletonBoxState();
}

class _SkeletonBoxState extends State<SkeletonBox>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _animation = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder: (context, child) => Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(widget.borderRadius),
          gradient: LinearGradient(
            begin: Alignment(_animation.value - 1, 0),
            end: Alignment(_animation.value, 0),
            colors: [
              AppTheme.navyBlue.withValues(alpha: 0.06),
              AppTheme.navyBlue.withValues(alpha: 0.12),
              AppTheme.navyBlue.withValues(alpha: 0.06),
            ],
          ),
        ),
      ),
    );
  }
}

/// Skeleton for a post card in the feed
class SkeletonPostCard extends StatelessWidget {
  const SkeletonPostCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Author row
          Row(
            children: [
              const SkeletonBox(width: 40, height: 40, borderRadius: 11),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: const [
                  SkeletonBox(width: 100, height: 12),
                  SizedBox(height: 4),
                  SkeletonBox(width: 60, height: 10),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          // Content lines
          const SkeletonBox(width: double.infinity, height: 12),
          const SizedBox(height: 6),
          const SkeletonBox(width: double.infinity, height: 12),
          const SizedBox(height: 6),
          const SkeletonBox(width: 200, height: 12),
          const SizedBox(height: 14),
          // Action row
          Row(
            children: const [
              SkeletonBox(width: 50, height: 10),
              SizedBox(width: 20),
              SkeletonBox(width: 50, height: 10),
              SizedBox(width: 20),
              SkeletonBox(width: 50, height: 10),
            ],
          ),
        ],
      ),
    );
  }
}

/// Skeleton for a group discovery card
class SkeletonGroupCard extends StatelessWidget {
  const SkeletonGroupCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppTheme.cardSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: [
          const SkeletonBox(width: 44, height: 44, borderRadius: 12),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SkeletonBox(width: 140, height: 13),
                SizedBox(height: 4),
                SkeletonBox(width: 200, height: 10),
                SizedBox(height: 4),
                SkeletonBox(width: 80, height: 10),
              ],
            ),
          ),
          const SkeletonBox(width: 56, height: 32, borderRadius: 20),
        ],
      ),
    );
  }
}

/// Skeleton list — shows N skeleton items
class SkeletonFeedList extends StatelessWidget {
  final int count;
  const SkeletonFeedList({super.key, this.count = 4});

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: count,
      itemBuilder: (_, __) => const SkeletonPostCard(),
    );
  }
}

class SkeletonGroupList extends StatelessWidget {
  final int count;
  const SkeletonGroupList({super.key, this.count = 5});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: List.generate(count, (_) => const SkeletonGroupCard()),
      ),
    );
  }
}

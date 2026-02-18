import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:go_router/go_router.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../routes/app_routes.dart';
import '../../providers/notification_provider.dart';
import '../discover/discover_screen.dart';
import '../secure_chat/secure_chat_full_screen.dart';

/// Unified shell for full-screen pages that sit outside the main tab navigation.
/// Provides a consistent top bar with back button, title, and standard actions
/// (home, search, messages) matching the thread screen pattern.
class FullScreenShell extends ConsumerWidget {
  /// The page title displayed in the app bar.
  final Widget? title;

  /// Simple string title — convenience alternative to [title] widget.
  final String? titleText;

  /// The page body content.
  final Widget body;

  /// Extra action buttons inserted *before* the standard home/search/messages.
  final List<Widget>? leadingActions;

  /// Whether to show the standard Home button in actions.
  final bool showHome;

  /// Whether to show the standard Search button in actions.
  final bool showSearch;

  /// Whether to show the standard Messages button (with badge) in actions.
  final bool showMessages;

  /// Optional bottom widget for the AppBar (e.g. TabBar).
  final PreferredSizeWidget? bottom;

  /// Optional floating action button.
  final Widget? floatingActionButton;

  /// Optional bottom navigation bar.
  final Widget? bottomNavigationBar;

  const FullScreenShell({
    super.key,
    this.title,
    this.titleText,
    required this.body,
    this.leadingActions,
    this.showHome = true,
    this.showSearch = true,
    this.showMessages = true,
    this.bottom,
    this.floatingActionButton,
    this.bottomNavigationBar,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      appBar: _buildAppBar(context, ref),
      body: body,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, WidgetRef ref) {
    return AppBar(
      backgroundColor: AppTheme.scaffoldBg,
      elevation: 0,
      surfaceTintColor: SojornColors.transparent,
      leading: IconButton(
        onPressed: () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          } else {
            context.go(AppRoutes.homeAlias);
          }
        },
        icon: Icon(Icons.arrow_back, color: AppTheme.navyBlue),
      ),
      title: title ?? (titleText != null
          ? Text(
              titleText!,
              style: GoogleFonts.inter(
                color: AppTheme.textPrimary,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            )
          : null),
      actions: _buildActions(context, ref),
      bottom: bottom,
    );
  }

  List<Widget> _buildActions(BuildContext context, WidgetRef ref) {
    final actions = <Widget>[];

    // Extra screen-specific actions first
    if (leadingActions != null) {
      actions.addAll(leadingActions!);
    }

    if (showHome) {
      actions.add(
        IconButton(
          onPressed: () {
            // Pop any Navigator-managed overlays before GoRouter navigates home
            final nav = Navigator.of(context, rootNavigator: true);
            if (nav.canPop()) nav.popUntil((r) => r.isFirst);
            context.go(AppRoutes.homeAlias);
          },
          icon: Icon(Icons.home_outlined, color: AppTheme.navyBlue),
        ),
      );
    }

    if (showSearch) {
      actions.add(
        IconButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(
              builder: (_) => const DiscoverScreen(),
              fullscreenDialog: true,
            ),
          ),
          icon: Icon(Icons.search, color: AppTheme.navyBlue),
        ),
      );
    }

    if (showMessages) {
      actions.add(
        IconButton(
          onPressed: () => Navigator.of(context, rootNavigator: true).push(
            MaterialPageRoute(
              builder: (_) => const SecureChatFullScreen(),
              fullscreenDialog: true,
            ),
          ),
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
      );
    }

    actions.add(const SizedBox(width: 8));
    return actions;
  }
}

// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/auth_service.dart';

import '../../models/post.dart';
import '../../providers/api_provider.dart';
import '../../providers/feed_refresh_provider.dart';
import '../../theme/tokens.dart';
import '../sojorn_snackbar.dart';

/// Post menu with kebab menu for owner actions (edit/delete)
/// and admin moderation actions (warn & remove).
class PostMenu extends ConsumerStatefulWidget {
  final Post post;
  final VoidCallback? onPostDeleted;

  const PostMenu({
    super.key,
    required this.post,
    this.onPostDeleted,
  });

  @override
  ConsumerState<PostMenu> createState() => _PostMenuState();
}

class _PostMenuState extends ConsumerState<PostMenu> {
  bool _isLoading = false;
  static const Map<String, String> _privacyLabels = {
    'public': 'Public',
    'followers': 'Followers',
    'private': 'Only me',
  };

  bool get _canEdit {
    final now = DateTime.now();
    final createdAt = widget.post.createdAt;
    return now.difference(createdAt).inMinutes < 2;
  }

  /// Check if current user is the post owner
  bool get _isOwner {
    final currentUserId = AuthService.instance.currentUser?.id;
    return currentUserId == widget.post.authorId;
  }

  bool get _isAdmin => AuthService.instance.isAdmin;

  bool get _isPinned => widget.post.pinnedAt != null;

  Future<void> _handleEdit() async {
    final TextEditingController controller =
        TextEditingController(text: widget.post.body);
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Edit Post'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            maxLength: 500,
            maxLines: 5,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Post cannot be empty';
              }
              return null;
            },
            decoration: const InputDecoration(
              hintText: 'What\'s on your mind?',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                Navigator.of(context).pop(controller.text.trim());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      setState(() => _isLoading = true);
      try {
        await ref.read(apiServiceProvider).editPost(
              postId: widget.post.id,
              content: result,
            );

        sojornSnackbar.showSuccess(
          context: context,
          message: 'Post updated successfully',
        );

        // Refresh feed to show updated post
        ref.read(feedRefreshProvider.notifier).increment();
        widget.onPostDeleted?.call();
      } catch (e) {
        sojornSnackbar.showError(
          context: context,
          message: e.toString().replaceAll('Exception: ', ''),
        );
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _handleDelete() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Post'),
        content: const Text(
            'Are you sure you want to delete this post? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: SojornColors.destructive),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: SojornColors.basicWhite)),
          ),
        ],
      ),
    );

    if (confirm == true) {
      setState(() => _isLoading = true);
      try {
        await ref.read(apiServiceProvider).deletePost(widget.post.id);

        sojornSnackbar.showSuccess(
          context: context,
          message: 'Post deleted',
        );

        // Refresh feed to remove deleted post immediately
        ref.read(feedRefreshProvider.notifier).increment();
        widget.onPostDeleted?.call();
      } catch (e) {
        sojornSnackbar.showError(
          context: context,
          message: e.toString().replaceAll('Exception: ', ''),
        );
      } finally {
        if (mounted) {
          setState(() => _isLoading = false);
        }
      }
    }
  }

  Future<void> _handlePrivacy() async {
    String selected = widget.post.visibility;

    final result = await showModalBottomSheet<String>(
      context: context,
      useSafeArea: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Post privacy'),
                  const SizedBox(height: 8),
                  ..._privacyLabels.entries.map((entry) {
                    return RadioListTile<String>(
                      value: entry.key,
                      groupValue: selected,
                      title: Text(entry.value),
                      onChanged: (value) {
                        if (value == null) return;
                        setModalState(() => selected = value);
                      },
                    );
                  }),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () => Navigator.of(context).pop(selected),
                      child: const Text('Save'),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    if (result == null || result == widget.post.visibility) {
      return;
    }

    setState(() => _isLoading = true);
    try {
      await ref.read(apiServiceProvider).updatePostVisibility(
            postId: widget.post.id,
            visibility: result,
          );

      sojornSnackbar.showSuccess(
        context: context,
        message: 'Post privacy updated',
      );

      // Refresh feed to show privacy changes
      ref.read(feedRefreshProvider.notifier).increment();
      widget.onPostDeleted?.call();
    } catch (e) {
      sojornSnackbar.showError(
        context: context,
        message: e.toString().replaceAll('Exception: ', ''),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handlePinToggle() async {
    setState(() => _isLoading = true);
    try {
      final apiService = ref.read(apiServiceProvider);
      if (_isPinned) {
        await apiService.unpinPost(widget.post.id);
        sojornSnackbar.showSuccess(
          context: context,
          message: 'Post unpinned',
        );
      } else {
        await apiService.pinPost(widget.post.id);
        sojornSnackbar.showSuccess(
          context: context,
          message: 'Post pinned to your profile',
        );
      }

      // Refresh feed to show pin state changes
      ref.read(feedRefreshProvider.notifier).increment();
      widget.onPostDeleted?.call();
    } catch (e) {
      sojornSnackbar.showError(
        context: context,
        message: e.toString().replaceAll('Exception: ', ''),
      );
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // ── Admin Moderation Actions ──────────────────────────────────────────

  Future<void> _handleAdminWarn() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final message = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Send Warning'),
        content: Form(
          key: formKey,
          child: TextFormField(
            controller: controller,
            maxLength: 500,
            maxLines: 3,
            autofocus: true,
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter a reason';
              }
              return null;
            },
            decoration: const InputDecoration(
              hintText: 'Reason for warning...',
              border: OutlineInputBorder(),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: SojornColors.destructive,
            ),
            onPressed: () {
              if (formKey.currentState?.validate() == true) {
                Navigator.of(context).pop(controller.text.trim());
              }
            },
            child: const Text('Warn & Remove',
                style: TextStyle(color: SojornColors.basicWhite)),
          ),
        ],
      ),
    );

    if (message == null || message.isEmpty) return;

    setState(() => _isLoading = true);
    try {
      await ref.read(apiServiceProvider).adminWarnUser(
            postId: widget.post.id,
            userId: widget.post.authorId,
            message: message,
            contentType: 'post',
          );

      if (mounted) {
        sojornSnackbar.showSuccess(
          context: context,
          message: 'Warning sent, post removed',
        );
        ref.read(feedRefreshProvider.notifier).increment();
        widget.onPostDeleted?.call();
      }
    } catch (e) {
      if (mounted) {
        sojornSnackbar.showError(
          context: context,
          message: e.toString().replaceAll('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _handleAdminRemove() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Post'),
        content: const Text(
            'Remove this post without sending a warning to the user?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: SojornColors.destructive,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove',
                style: TextStyle(color: SojornColors.basicWhite)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    setState(() => _isLoading = true);
    try {
      await ref.read(apiServiceProvider).adminWarnUser(
            postId: widget.post.id,
            userId: widget.post.authorId,
            message: 'Post removed by moderator',
            contentType: 'post',
          );

      if (mounted) {
        sojornSnackbar.showSuccess(
          context: context,
          message: 'Post removed',
        );
        ref.read(feedRefreshProvider.notifier).increment();
        widget.onPostDeleted?.call();
      }
    } catch (e) {
      if (mounted) {
        sojornSnackbar.showError(
          context: context,
          message: e.toString().replaceAll('Exception: ', ''),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Show menu for owners or admins
    if (!_isOwner && !_isAdmin) {
      return const SizedBox.shrink();
    }

    return PopupMenuButton<String>(
      onSelected: (value) {
        switch (value) {
          case 'edit':
            _handleEdit();
          case 'privacy':
            _handlePrivacy();
          case 'pin':
            _handlePinToggle();
          case 'delete':
            _handleDelete();
          case 'admin_warn':
            _handleAdminWarn();
          case 'admin_remove':
            _handleAdminRemove();
        }
      },
      itemBuilder: (context) => [
        // Owner actions
        if (_isOwner) ...[
          if (_canEdit)
            const PopupMenuItem(
              value: 'edit',
              child: Row(
                children: [
                  Icon(Icons.edit, size: 20),
                  SizedBox(width: 8),
                  Text('Edit'),
                ],
              ),
            ),
          const PopupMenuItem(
            value: 'privacy',
            child: Row(
              children: [
                Icon(Icons.lock_outline, size: 20),
                SizedBox(width: 8),
                Text('Edit privacy'),
              ],
            ),
          ),
          PopupMenuItem(
            value: 'pin',
            child: Row(
              children: [
                Icon(_isPinned ? Icons.push_pin : Icons.push_pin_outlined, size: 20),
                const SizedBox(width: 8),
                Text(_isPinned ? 'Unpin from profile' : 'Pin to profile'),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'delete',
            child: Row(
              children: [
                Icon(Icons.delete_outline, size: 20, color: SojornColors.destructive),
                SizedBox(width: 8),
                Text('Delete', style: TextStyle(color: SojornColors.destructive)),
              ],
            ),
          ),
        ],
        // Admin actions (for non-owned posts)
        if (_isAdmin && !_isOwner) ...[
          const PopupMenuItem(
            value: 'admin_warn',
            child: Row(
              children: [
                Icon(Icons.warning_amber_outlined, size: 20, color: Colors.orange),
                SizedBox(width: 8),
                Text('Warn & Remove', style: TextStyle(color: Colors.orange)),
              ],
            ),
          ),
          const PopupMenuItem(
            value: 'admin_remove',
            child: Row(
              children: [
                Icon(Icons.delete_sweep_outlined, size: 20, color: SojornColors.destructive),
                SizedBox(width: 8),
                Text('Remove', style: TextStyle(color: SojornColors.destructive)),
              ],
            ),
          ),
        ],
      ],
      icon: const Icon(Icons.more_vert),
    );
  }
}

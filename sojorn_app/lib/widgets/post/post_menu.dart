import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../services/auth_service.dart';

import '../../models/post.dart';
import '../../providers/api_provider.dart';
import '../../providers/feed_refresh_provider.dart';
import '../../theme/tokens.dart';
import '../sojorn_snackbar.dart';

/// Post menu with kebab menu for owner actions (edit/delete).
///
/// Shows "Edit" only within 2 minutes of creation.
/// Shows "Delete" for owners.
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

  @override
  Widget build(BuildContext context) {
    if (!_isOwner) {
      return const SizedBox.shrink();
    }

    return PopupMenuButton<String>(
      onSelected: (value) {
        switch (value) {
          case 'edit':
            _handleEdit();
            break;
          case 'privacy':
            _handlePrivacy();
            break;
          case 'pin':
            _handlePinToggle();
            break;
          case 'delete':
            _handleDelete();
            break;
        }
      },
      itemBuilder: (context) => [
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
      icon: const Icon(Icons.more_vert),
    );
  }
}

import 'package:flutter/material.dart';
import '../../models/secure_chat.dart';
import '../../services/secure_chat_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/media/signed_media_image.dart';

/// Bottom sheet for starting a new secure conversation
class NewConversationSheet extends StatefulWidget {
  final void Function(SecureConversation) onConversationStarted;

  const NewConversationSheet({
    super.key,
    required this.onConversationStarted,
  });

  @override
  State<NewConversationSheet> createState() => _NewConversationSheetState();
}

class _NewConversationSheetState extends State<NewConversationSheet> {
  final SecureChatService _chatService = SecureChatService();

  List<MutualFollow> _mutualFollows = [];
  bool _isLoading = true;
  bool _isStarting = false;
  String? _error;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadMutualFollows();
  }

  Future<void> _loadMutualFollows() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final follows = await _chatService.getMutualFollows();
      if (mounted) {
        setState(() {
          _mutualFollows = follows;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load contacts';
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _startConversation(MutualFollow user) async {
    setState(() => _isStarting = true);

    try {
      final conversation = await _chatService.getOrCreateConversation(user.userId);
      if (conversation != null && mounted) {
        widget.onConversationStarted(conversation);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Could not start conversation')),
          );
          setState(() => _isStarting = false);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
        setState(() => _isStarting = false);
      }
    }
  }

  List<MutualFollow> get _filteredFollows {
    if (_searchQuery.isEmpty) return _mutualFollows;

    final query = _searchQuery.toLowerCase();
    return _mutualFollows.where((user) {
      return user.handle.toLowerCase().contains(query) ||
          (user.displayName?.toLowerCase().contains(query) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.8,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppTheme.textDisabled.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: AppTheme.ksuPurple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.person_add_outlined,
                    color: AppTheme.ksuPurple,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'New Conversation',
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: AppTheme.navyBlue,
                            ),
                      ),
                      Text(
                        'Select someone you mutually follow',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: AppTheme.textDisabled,
                            ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),

          // Search bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: TextField(
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: 'Search...',
                prefixIcon: const Icon(Icons.search, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppTheme.egyptianBlue),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),
          const Divider(height: 1),

          // Content
          Expanded(
            child: _buildContent(),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: AppTheme.error),
            const SizedBox(height: 16),
            Text(_error!, style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _loadMutualFollows,
              icon: const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      );
    }

    if (_mutualFollows.isEmpty) {
      return _buildEmptyState();
    }

    final filtered = _filteredFollows;
    if (filtered.isEmpty) {
      return Center(
        child: Text(
          'No matches found',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: AppTheme.textDisabled,
              ),
        ),
      );
    }

    return Stack(
      children: [
        ListView.separated(
          padding: const EdgeInsets.symmetric(vertical: 8),
          itemCount: filtered.length,
          separatorBuilder: (_, __) => const Divider(height: 1, indent: 72),
          itemBuilder: (context, index) => _buildUserTile(filtered[index]),
        ),
        if (_isStarting)
          Container(
            color: const Color(0x42000000),
            child: const Center(child: CircularProgressIndicator()),
          ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.people_outline,
              size: 64,
              color: AppTheme.textDisabled,
            ),
            const SizedBox(height: 16),
            Text(
              'No Mutual Follows',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppTheme.navyBlue,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              'Secure messaging is only available between users who mutually follow each other.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textDisabled,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppTheme.ksuPurple.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: AppTheme.ksuPurple,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      'Follow someone and have them follow you back to start chatting',
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: AppTheme.ksuPurple,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserTile(MutualFollow user) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      leading: CircleAvatar(
        radius: 24,
        backgroundColor: AppTheme.egyptianBlue.withValues(alpha: 0.1),
        child: user.avatarUrl != null
            ? ClipOval(
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: SignedMediaImage(
                    url: user.avatarUrl!,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                  ),
                ),
              )
            : Text(
                user.handle.isNotEmpty ? user.handle[0].toUpperCase() : '?',
                style: TextStyle(
                  color: AppTheme.egyptianBlue,
                  fontWeight: FontWeight.bold,
                ),
              ),
      ),
      title: Text(
        user.displayName ?? '@${user.handle}',
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: AppTheme.navyBlue,
            ),
      ),
      subtitle: user.displayName != null
          ? Text(
              '@${user.handle}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: AppTheme.textDisabled,
                  ),
            )
          : null,
      trailing: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: AppTheme.ksuPurple,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.lock, size: 14, color: SojornColors.basicWhite),
            const SizedBox(width: 4),
            Text(
              'Chat',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: SojornColors.basicWhite,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ],
        ),
      ),
      onTap: _isStarting ? null : () => _startConversation(user),
    );
  }
}

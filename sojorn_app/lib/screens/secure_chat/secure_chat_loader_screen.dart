// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import '../../services/secure_chat_service.dart';
import '../../theme/app_theme.dart';
import 'secure_chat_screen.dart';

/// Loading wrapper to fetch conversation data before showing chat screen
class SecureChatLoaderScreen extends StatefulWidget {
  final String conversationId;

  const SecureChatLoaderScreen({
    super.key,
    required this.conversationId,
  });

  @override
  State<SecureChatLoaderScreen> createState() => _SecureChatLoaderScreenState();
}

class _SecureChatLoaderScreenState extends State<SecureChatLoaderScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadConversation();
  }

  Future<void> _loadConversation() async {
    try {
      final conversation = await SecureChatService.instance
          .getConversationById(widget.conversationId);

      if (!mounted) return;

      if (conversation != null) {
        // Replace this loader with the actual chat screen
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => SecureChatScreen(conversation: conversation),
          ),
        );
      } else {
        setState(() {
          _error = 'Conversation not found';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Failed to load conversation: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(_error!, style: TextStyle(color: AppTheme.error)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Go Back'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppTheme.scaffoldBg,
      body: const Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

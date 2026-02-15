import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class AdminUserBaseScreen extends StatelessWidget {
  const AdminUserBaseScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('User Base'),
        actions: [
          IconButton(
            tooltip: 'Moderation Queue',
            onPressed: () => context.go('/admin/moderation'),
            icon: const Icon(Icons.policy),
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'User Management',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 12),
            Text(
              'Search, ban/unban, and review strike history here.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }
}

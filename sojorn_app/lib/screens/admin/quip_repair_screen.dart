// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/api_provider.dart';

class QuipRepairScreen extends ConsumerStatefulWidget {
  const QuipRepairScreen({super.key});

  @override
  ConsumerState<QuipRepairScreen> createState() => _QuipRepairScreenState();
}

class _QuipRepairScreenState extends ConsumerState<QuipRepairScreen> {
  List<Map<String, dynamic>> _brokenQuips = [];
  bool _isLoading = false;
  bool _isRepairing = false;
  String? _statusMessage;

  @override
  void initState() {
    super.initState();
    _fetchBrokenQuips();
  }

  Future<void> _fetchBrokenQuips() async {
    setState(() { _isLoading = true; _statusMessage = null; });
    try {
      final api = ref.read(apiServiceProvider);
      final data = await api.callGoApi('/admin/quips/broken', method: 'GET');
      final quips = (data['quips'] as List?)?.cast<Map<String, dynamic>>() ?? [];
      if (mounted) setState(() => _brokenQuips = quips);
    } catch (e) {
      if (mounted) {
        setState(() => _statusMessage = 'Error loading broken quips: $e');
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _repairQuip(Map<String, dynamic> quip) async {
    setState(() => _isRepairing = true);
    try {
      final api = ref.read(apiServiceProvider);
      await api.callGoApi('/admin/quips/${quip['id']}/repair', method: 'POST');
      if (mounted) {
        setState(() {
          _brokenQuips.removeWhere((q) => q['id'] == quip['id']);
          _statusMessage = 'Fixed: ${quip['id']}';
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Repair failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isRepairing = false);
    }
  }

  Future<void> _repairAll() async {
    final list = List<Map<String, dynamic>>.from(_brokenQuips);
    for (final quip in list) {
      if (!mounted) break;
      await _repairQuip(quip);
    }
    if (mounted) setState(() => _statusMessage = 'Repair all complete');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Repair Thumbnails'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _fetchBrokenQuips,
            tooltip: 'Reload',
          ),
          if (_brokenQuips.isNotEmpty && !_isRepairing)
            IconButton(
              icon: const Icon(Icons.build),
              onPressed: _repairAll,
              tooltip: 'Repair All',
            ),
        ],
      ),
      body: Column(
        children: [
          if (_statusMessage != null)
            Container(
              padding: const EdgeInsets.all(8),
              width: double.infinity,
              color: const Color(0xFFFFC107).withValues(alpha: 0.2),
              child: Text(_statusMessage!, textAlign: TextAlign.center),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _brokenQuips.isEmpty
                    ? const Center(child: Text('No missing thumbnails found.'))
                    : ListView.builder(
                        itemCount: _brokenQuips.length,
                        itemBuilder: (context, index) {
                          final item = _brokenQuips[index];
                          return ListTile(
                            leading: const Icon(Icons.videocam_off),
                            title: Text(item['id'] as String? ?? ''),
                            subtitle: Text(item['created_at']?.toString() ?? ''),
                            trailing: _isRepairing
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : IconButton(
                                    icon: const Icon(Icons.auto_fix_high),
                                    onPressed: () => _repairQuip(item),
                                  ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

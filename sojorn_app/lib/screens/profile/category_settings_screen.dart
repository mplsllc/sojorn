// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/category.dart';
import '../../providers/api_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../widgets/app_scaffold.dart';

class CategoryDiscoveryScreen extends ConsumerStatefulWidget {
  const CategoryDiscoveryScreen({super.key});

  @override
  ConsumerState<CategoryDiscoveryScreen> createState() => _CategoryDiscoveryScreenState();
}

class _CategoryDiscoveryScreenState extends ConsumerState<CategoryDiscoveryScreen> {
  bool _isLoading = true;
  List<Category> _categories = [];
  Map<String, bool> _settings = {};

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      final apiService = ref.read(apiServiceProvider);
      final catsResponse = await apiService.callGoApi('/categories', method: 'GET');
      final settingsResponse = await apiService.callGoApi('/categories/settings', method: 'GET');
      
      final List<dynamic> catsJson = catsResponse['categories'] ?? [];
      final List<dynamic> settingsJson = settingsResponse['settings'] ?? [];
      
      final cats = catsJson.map((j) => Category.fromJson(j)).toList();
      final settingsMap = { for (var s in settingsJson) s['category_id'] as String : s['enabled'] as bool };

      if (mounted) {
        setState(() {
          _categories = cats;
          // Default to !defaultOff if no setting exists
          _settings = { for (var c in cats) c.id : settingsMap[c.id] ?? !c.defaultOff };
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleCategory(String catId, bool enabled) async {
    final oldVal = _settings[catId];
    setState(() => _settings[catId] = enabled);
    
    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.callGoApi('/categories/settings', method: 'POST', body: {
        'category_id': catId,
        'enabled': enabled,
      });
    } catch (e) {
      setState(() => _settings[catId] = oldVal ?? false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AppScaffold(
      title: 'Discovery Cohorts',
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView.builder(
              padding: const EdgeInsets.all(AppTheme.spacingLg),
              itemCount: _categories.length,
              itemBuilder: (context, index) {
                final cat = _categories[index];
                return Container(
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: SojornColors.basicWhite,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: AppTheme.egyptianBlue.withValues(alpha: 0.1)),
                  ),
                  child: SwitchListTile(
                    activeColor: AppTheme.brightNavy,
                    title: Text(cat.name, style: AppTheme.textTheme.labelLarge),
                    subtitle: Text(cat.description, style: AppTheme.textTheme.bodySmall),
                    value: _settings[cat.id] ?? false,
                    onChanged: (v) => _toggleCategory(cat.id, v),
                  ),
                );
              },
            ),
    );
  }
}

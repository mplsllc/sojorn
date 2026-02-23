// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../models/category.dart';
import '../../providers/api_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import '../../routes/app_routes.dart';
import '../../providers/onboarding_provider.dart';

final categoriesProvider = FutureProvider<List<Category>>((ref) {
  final apiService = ref.watch(apiServiceProvider);
  return apiService.getCategories();
});

class CategorySelectScreen extends ConsumerStatefulWidget {
  const CategorySelectScreen({super.key});

  @override
  ConsumerState<CategorySelectScreen> createState() =>
      _CategorySelectScreenState();
}

class _CategorySelectScreenState extends ConsumerState<CategorySelectScreen> {
  final Set<String> _selectedCategoryIds = {};
  bool _isLoading = false;
  bool _initialized = false;
  String? _errorMessage;

  Future<void> _saveSelection(List<Category> categories) async {
    if (_selectedCategoryIds.isEmpty) {
      setState(() {
        _errorMessage = 'Select at least one category to continue.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.setUserCategorySettings(
        categories: categories,
        enabledCategoryIds: _selectedCategoryIds,
      );
      
      // Mark onboarding as complete once categories are selected
      await apiService.completeOnboarding();

      // IMPORTANT: Invalidate the providers that AuthGate and other screens listen to
      ref.invalidate(profileExistsProvider);
      ref.invalidate(categorySelectionProvider);

      if (mounted) {
        // Navigation might be handled by AuthGate automatically now, 
        // but explicit navigation to home is safe.
        context.go(AppRoutes.homeAlias);
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsyncValue = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Your Interests'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppTheme.spacingLg),
          child: categoriesAsyncValue.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (error, stack) => Center(
              child: Text('Error loading categories: $error'),
            ),
            data: (categories) {
              if (!_initialized) {
                _initialized = true;
                _selectedCategoryIds.addAll(
                  categories
                      .where((category) => !category.defaultOff)
                      .map((category) => category.id),
                );
              }

              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Follow your favorite hashtags',
                    style: AppTheme.headlineMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppTheme.spacingSm),
                  Text(
                    'We\'ll use this to personalize your feed. You can adjust this anytime.',
                    style: AppTheme.bodyMedium.copyWith(
                      color: AppTheme.navyText.withValues(alpha: 0.8), // Replaced AppTheme.textSecondary
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: AppTheme.spacingLg),
                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(AppTheme.spacingMd),
                      decoration: BoxDecoration(
                        color: AppTheme.error.withValues(alpha: 0.1), // Replaced withValues
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: AppTheme.error, width: 1),
                      ),
                      child: Text(
                        _errorMessage!,
                        style: AppTheme.textTheme.labelSmall?.copyWith( // Replaced bodySmall
                          color: AppTheme.error,
                        ),
                      ),
                    ),
                    const SizedBox(height: AppTheme.spacingLg),
                  ],
                  Expanded(
                    child: ListView.separated(
                      itemCount: categories.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: AppTheme.spacingSm),
                      itemBuilder: (context, index) {
                        final category = categories[index];
                        final isSelected =
                            _selectedCategoryIds.contains(category.id);

                        return Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: isSelected
                                  ? AppTheme.brightNavy // Replaced AppTheme.accent
                                  : AppTheme.egyptianBlue, // Replaced AppTheme.border
                            ),
                          ),
                          child: CheckboxListTile(
                            value: isSelected,
                            onChanged: (value) {
                              setState(() {
                                if (value == true) {
                                  _selectedCategoryIds.add(category.id);
                                } else {
                                  _selectedCategoryIds.remove(category.id);
                                }
                              });
                            },
                            title: Text('#${category.name.toLowerCase()}'),
                            subtitle: category.description.isNotEmpty ? Text(category.description) : null,
                            controlAffinity: ListTileControlAffinity.leading,
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: AppTheme.spacingMd),
                  ElevatedButton(
                    onPressed: _isLoading
                        ? null
                        : () => _saveSelection(categories),
                    child: _isLoading
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation(SojornColors.basicWhite),
                            ),
                          )
                        : const Text('Continue'),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

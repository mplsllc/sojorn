// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/api_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';
import 'category_select_screen.dart';

class ProfileSetupScreen extends ConsumerStatefulWidget {
  const ProfileSetupScreen({super.key});

  @override
  ConsumerState<ProfileSetupScreen> createState() =>
      _ProfileSetupScreenState();
}

class _ProfileSetupScreenState extends ConsumerState<ProfileSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _handleController = TextEditingController();
  final _displayNameController = TextEditingController();
  final _bioController = TextEditingController();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _handleController.dispose();
    _displayNameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  Future<void> _createProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final apiService = ref.read(apiServiceProvider);
      await apiService.createProfile(
        handle: _handleController.text.trim(),
        displayName: _displayNameController.text.trim(),
        bio: _bioController.text.trim().isEmpty
            ? null
            : _bioController.text.trim(),
      );

      // Profile created successfully, move to category selection
      if (mounted) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => const CategorySelectScreen(),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString().replaceAll('Exception: ', '');
      });
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  String? _validateHandle(String? value) {
    if (value == null || value.isEmpty) {
      return 'Handle is required';
    }

    // Must be 3-20 characters, lowercase letters, numbers, and underscores only
    final handleRegex = RegExp(r'^[a-z0-9_]{3,20}$');
    if (!handleRegex.hasMatch(value)) {
      return 'Handle must be 3-20 characters (a-z, 0-9, _)';
    }

    return null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Create Profile'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTheme.spacingLg),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 400),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Instructions
                    Text(
                      'Choose your identity',
                      style: AppTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppTheme.spacingSm),

                    Text(
                      'Your handle is permanent. Choose thoughtfully.',
                      style: AppTheme.bodyMedium.copyWith(
                        color: AppTheme.navyText.withValues(alpha: 0.8), // Replaced AppTheme.textSecondary
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: AppTheme.spacingLg * 1.5), // Replaced AppTheme.spacing2xl

                    // Error message
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
                          style: AppTheme.textTheme.labelSmall?.copyWith( // Replaced AppTheme.bodySmall
                            color: AppTheme.error,
                          ),
                        ),
                      ),
                      const SizedBox(height: AppTheme.spacingLg),
                    ],

                    // Handle field
                    TextFormField(
                      controller: _handleController,
                      decoration: const InputDecoration(
                        labelText: 'Handle',
                        hintText: 'your_handle',
                        prefixText: '@',
                      ),
                      validator: _validateHandle,
                      onChanged: (value) {
                        // Force lowercase
                        final lowercase = value.toLowerCase();
                        if (lowercase != value) {
                          _handleController.value = TextEditingValue(
                            text: lowercase,
                            selection: _handleController.selection,
                          );
                        }
                      },
                    ),
                    const SizedBox(height: AppTheme.spacingMd),

                    // Display name field
                    TextFormField(
                      controller: _displayNameController,
                      decoration: const InputDecoration(
                        labelText: 'Display Name',
                        hintText: 'Your Name',
                      ),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Display name is required';
                        }
                        if (value.length > 50) {
                          return 'Display name must be 50 characters or less';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppTheme.spacingMd),

                    // Bio field (optional)
                    TextFormField(
                      controller: _bioController,
                      maxLines: 3,
                      maxLength: 300,
                      decoration: const InputDecoration(
                        labelText: 'Bio (optional)',
                        hintText: 'A few words about yourself',
                        alignLabelWithHint: true,
                      ),
                      validator: (value) {
                        if (value != null && value.length > 300) {
                          return 'Bio must be 300 characters or less';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: AppTheme.spacingLg),

                    // Create profile button
                    ElevatedButton(
                      onPressed: _isLoading ? null : _createProfile,
                      child: _isLoading
                          ? const SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor:
                                    AlwaysStoppedAnimation(SojornColors.basicWhite),
                              ),
                            )
                          : const Text('Begin Journey'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
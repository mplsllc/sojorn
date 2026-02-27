// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/group.dart';
import '../providers/api_provider.dart';
import '../services/analytics_service.dart';
import '../theme/app_theme.dart';
import 'media/sojorn_avatar.dart';
import '../utils/error_handler.dart';

/// Multi-step modal for creating a new group
class GroupCreationModal extends ConsumerStatefulWidget {
  const GroupCreationModal({super.key});

  @override
  ConsumerState<GroupCreationModal> createState() => _GroupCreationModalState();
}

class _GroupCreationModalState extends ConsumerState<GroupCreationModal> {
  int _currentStep = 0;
  final _formKey = GlobalKey<FormState>();
  
  // Basic info
  final _nameController = TextEditingController();
  final _descriptionController = TextEditingController();
  GroupCategory _selectedCategory = GroupCategory.general;
  bool _isPrivate = false;
  
  // Visuals
  String? _avatarUrl;
  String? _bannerUrl;
  
  bool _isLoading = false;

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _createGroup() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      final api = ref.read(apiServiceProvider);
      final result = await api.createGroup(
        name: _nameController.text.trim(),
        description: _descriptionController.text.trim(),
        category: _selectedCategory,
        isPrivate: _isPrivate,
        avatarUrl: _avatarUrl,
        bannerUrl: _bannerUrl,
      );

      if (mounted) {
        AnalyticsService.instance.event('group_created', value: _isPrivate ? 'private' : 'public');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Group created successfully!'),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
          ),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        ErrorHandler.handleError(e, context: context);
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Widget _buildStepIndicator() {
    return Row(
      children: [
        for (int i = 0; i < 3; i++) ...[
          Expanded(
            child: Container(
              height: 4,
              decoration: BoxDecoration(
                color: i <= _currentStep ? AppTheme.navyBlue : AppTheme.borderSubtle,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          if (i < 2) const SizedBox(width: 8),
        ],
      ],
    );
  }

  Widget _buildStep1() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Basic Information',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppTheme.navyBlue,
          ),
        ),
        const SizedBox(height: 20),
        
        Form(
          key: _formKey,
          child: Column(
            children: [
              TextFormField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: 'Group Name',
                  hintText: 'Enter a unique name for your group',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                maxLength: 50,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Group name is required';
                  }
                  if (value.trim().length < 3) {
                    return 'Name must be at least 3 characters';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              
              TextFormField(
                controller: _descriptionController,
                decoration: InputDecoration(
                  labelText: 'Description',
                  hintText: 'What is this group about?',
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                maxLines: 3,
                maxLength: 300,
              ),
              const SizedBox(height: 16),
              
              Text(
                'Category',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: GroupCategory.values.map((category) {
                  final isSelected = _selectedCategory == category;
                  return FilterChip(
                    label: Text(category.displayName),
                    selected: isSelected,
                    onSelected: (_) {
                      setState(() => _selectedCategory = category);
                    },
                    selectedColor: AppTheme.navyBlue.withValues(alpha: 0.1),
                    labelStyle: TextStyle(
                      color: isSelected ? AppTheme.navyBlue : Colors.black87,
                    ),
                    side: BorderSide(
                      color: isSelected ? AppTheme.navyBlue : AppTheme.borderSubtle,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              
              SwitchListTile(
                title: const Text('Private Group'),
                subtitle: const Text('Only approved members can join'),
                value: _isPrivate,
                onChanged: (value) {
                  setState(() => _isPrivate = value);
                },
                activeColor: AppTheme.navyBlue,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStep2() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Visuals',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppTheme.navyBlue,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Add personality to your group with images (optional)',
          style: TextStyle(
            fontSize: 14,
            color: AppTheme.textDisabled,
          ),
        ),
        const SizedBox(height: 20),
        
        // Avatar upload
        Container(
          height: 120,
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.borderSubtle),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              SojornAvatar(
                displayName: _nameController.text.trim(),
                avatarUrl: _avatarUrl,
                size: 64,
              ),
              const SizedBox(height: 8),
              TextButton(
                onPressed: () {
                  _showImageUploadDialog(context, 'avatar');
                },
                child: const Text('Upload Avatar'),
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 16),
        
        // Banner upload
        Container(
          height: 80,
          decoration: BoxDecoration(
            border: Border.all(color: AppTheme.borderSubtle),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.image_outlined, size: 32, color: AppTheme.textDisabled),
              const SizedBox(height: 4),
              TextButton(
                onPressed: () {
                  _showImageUploadDialog(context, 'banner');
                },
                child: const Text('Upload Banner'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildStep3() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Review & Create',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: AppTheme.navyBlue,
          ),
        ),
        const SizedBox(height: 20),
        
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppTheme.cardSurface,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.1)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 24,
                    backgroundColor: AppTheme.navyBlue.withValues(alpha: 0.1),
                    child: Icon(Icons.group, size: 24, color: AppTheme.navyBlue.withValues(alpha: 0.3)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _nameController.text.trim(),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _getCategoryColor(_selectedCategory).withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _selectedCategory.displayName,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: _getCategoryColor(_selectedCategory),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_isPrivate)
                    Icon(Icons.lock, size: 16, color: AppTheme.textDisabled),
                ],
              ),
              if (_descriptionController.text.trim().isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  _descriptionController.text.trim(),
                  style: TextStyle(
                    fontSize: 14,
                    color: AppTheme.textDisabled,
                  ),
                ),
              ],
            ],
          ),
        ),
        
        const SizedBox(height: 20),
        
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.blue[50],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline, size: 16, color: Colors.blue[700]),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'You will automatically become the owner of this group.',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.blue[700],
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Color _getCategoryColor(GroupCategory category) {
    switch (category) {
      case GroupCategory.general:
        return AppTheme.navyBlue;
      case GroupCategory.hobby:
        return Colors.purple;
      case GroupCategory.sports:
        return Colors.green;
      case GroupCategory.professional:
        return Colors.blue;
      case GroupCategory.localBusiness:
        return Colors.orange;
      case GroupCategory.support:
        return Colors.pink;
      case GroupCategory.education:
        return Colors.teal;
    }
  }

  Widget _buildActions() {
    return Row(
      children: [
        if (_currentStep > 0)
          TextButton(
            onPressed: () {
              setState(() => _currentStep--);
            },
            child: const Text('Back'),
          ),
        const Spacer(),
        if (_currentStep < 2)
          ElevatedButton(
            onPressed: () {
              if (_currentStep == 0 && !_formKey.currentState!.validate()) return;
              setState(() => _currentStep++);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.navyBlue,
              foregroundColor: Colors.white,
            ),
            child: const Text('Next'),
          ),
        if (_currentStep == 2)
          ElevatedButton(
            onPressed: _isLoading ? null : _createGroup,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppTheme.navyBlue,
              foregroundColor: Colors.white,
            ),
            child: _isLoading
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation(Colors.white),
                    ),
                  )
                : const Text('Create Group'),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Container(
        width: 500,
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
                const Spacer(),
                Text(
                  'Create Group',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                const SizedBox(width: 48), // Balance the close button
              ],
            ),
            const SizedBox(height: 16),
            _buildStepIndicator(),
            const SizedBox(height: 24),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  children: [
                    if (_currentStep == 0) _buildStep1(),
                    if (_currentStep == 1) _buildStep2(),
                    if (_currentStep == 2) _buildStep3(),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            _buildActions(),
          ],
        ),
      ),
    );
  }

  void _showImageUploadDialog(BuildContext context, String type) {
    // This method will implement image upload functionality
    // For now, show a placeholder dialog
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Upload ${type == 'avatar' ? 'Avatar' : 'Banner'}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Choose image source:'),
            const SizedBox(height: 16),
            ListTile(
              leading: const Icon(Icons.camera),
              title: const Text('Take Photo'),
              onTap: () {
                Navigator.pop(context);
                _captureImage(type);
              },
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: const Text('Choose from Gallery'),
              onTap: () {
                Navigator.pop(context);
                _pickImageFromGallery(type);
              },
            ),
          ],
        ),
      ),
    );
  }

  void _captureImage(String type) {
    // Implement camera capture functionality
    print('Capture image for $type');
  }

  void _pickImageFromGallery(String type) {
    // Implement gallery picker functionality
    print('Pick image from gallery for $type');
  }
}

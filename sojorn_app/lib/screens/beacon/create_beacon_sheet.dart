import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import '../../models/beacon.dart';
import '../../models/post.dart';
import '../../providers/api_provider.dart';
import '../../services/image_upload_service.dart';
import '../../theme/tokens.dart';
import '../../theme/app_theme.dart';

class CreateBeaconSheet extends ConsumerStatefulWidget {
  final double centerLat;
  final double centerLong;
  final Function(Post post) onBeaconCreated;

  const CreateBeaconSheet({
    super.key,
    required this.centerLat,
    required this.centerLong,
    required this.onBeaconCreated,
  });

  @override
  ConsumerState<CreateBeaconSheet> createState() => _CreateBeaconSheetState();
}

class _CreateBeaconSheetState extends ConsumerState<CreateBeaconSheet> {
  final ImageUploadService _imageUploadService = ImageUploadService();
  final _descriptionController = TextEditingController();

  BeaconType _selectedType = BeaconType.safety;
  BeaconSeverity _selectedSeverity = BeaconSeverity.medium;
  bool _isSubmitting = false;
  bool _isUploadingImage = false;
  File? _selectedImage;
  String? _uploadedImageUrl;

  // User-chosen beacon location — defaults to map centre, updated by tapping the mini-map.
  // Stored as-is here; the server fuzzes to ~1 km before storage.
  late double _pickedLat;
  late double _pickedLong;
  late final MapController _mapController;

  final List<BeaconType> _types = [
    // Geo-Alerts (map)
    BeaconType.suspiciousActivity,
    BeaconType.hazard,
    BeaconType.fire,
    BeaconType.officialPresence,
    BeaconType.safety,
    BeaconType.checkpoint,
    BeaconType.taskForce,
    // Discussion (board)
    BeaconType.community,
    BeaconType.lostPet,
    BeaconType.question,
    BeaconType.event,
    BeaconType.resource,
  ];

  @override
  void initState() {
    super.initState();
    _pickedLat = widget.centerLat;
    _pickedLong = widget.centerLong;
    _mapController = MapController();
  }

  @override
  void dispose() {
    _descriptionController.dispose();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    setState(() => _isUploadingImage = true);

    try {
      final ImagePicker picker = ImagePicker();
      final XFile? image = await picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 85,
      );

      if (image == null) {
        setState(() => _isUploadingImage = false);
        return;
      }

      final file = File(image.path);
      setState(() => _selectedImage = file);

      final imageUrl = await _imageUploadService.uploadImage(file);

      if (mounted) {
        setState(() {
          _uploadedImageUrl = imageUrl;
          _isUploadingImage = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isUploadingImage = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not upload the photo: $e')),
        );
      }
    }
  }

  void _removeImage() {
    setState(() {
      _selectedImage = null;
      _uploadedImageUrl = null;
    });
  }

  Future<void> _submit() async {
    final description = _descriptionController.text.trim();

    if (description.length < 15) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text(
            'Please add more detail — describe what you see, where, and if it\'s still happening (at least 15 characters).')),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    debugPrint('[Beacon] submit — type=${_selectedType.value} severity=${_selectedSeverity.value} lat=~${_pickedLat.toStringAsFixed(2)} long=~${_pickedLong.toStringAsFixed(2)} hasImage=${_uploadedImageUrl != null}');

    try {
      final apiService = ref.read(apiServiceProvider);

      final body = _buildBeaconBody(
        description: description,
        lat: _pickedLat,
        long: _pickedLong,
        type: _selectedType,
      );

      final post = await apiService.createBeacon(
        body: body,
        beaconType: _selectedType.value,
        lat: _pickedLat,
        long: _pickedLong,
        severity: _selectedSeverity.value,
        imageUrl: _uploadedImageUrl,
      );

      debugPrint('[Beacon] created id=${post.id}');
      if (mounted) {
        widget.onBeaconCreated(post);
        Navigator.of(context).pop();
      }
    } catch (e) {
      debugPrint('[Beacon] ✗ create failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not create the report: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String get _hintText {
    switch (_selectedType) {
      case BeaconType.suspiciousActivity:
        return 'What are they doing? Still happening? Which direction?';
      case BeaconType.officialPresence:
        return 'How many units? On which street? Any visible activity?';
      case BeaconType.checkpoint:
        return 'Which direction is traffic stopped? Stationary or moving through?';
      case BeaconType.taskForce:
        return 'How many units or vehicles? Any visible activity?';
      case BeaconType.hazard:
        return 'What hazard? Which lane or direction is blocked?';
      case BeaconType.fire:
        return 'Smoke or active fire? Which side of the structure?';
      case BeaconType.safety:
        return 'Describe what happened. Anyone still in the area?';
      case BeaconType.community:
        return 'What\'s happening? When, where, who\'s welcome?';
      case BeaconType.lostPet:
        return 'Breed, color, name, collar? Where and when last seen?';
      case BeaconType.question:
        return 'What would you like your neighbors to know or answer?';
      case BeaconType.event:
        return 'Date, time, location, what to expect or bring?';
      case BeaconType.resource:
        return 'What are you offering or looking for? How to pick up?';
      case BeaconType.camera:
      case BeaconType.sign:
      case BeaconType.weatherStation:
        return '';
    }
  }

  String _buildBeaconBody({
    required String description,
    required double lat,
    required double long,
    required BeaconType type,
  }) {
    return description;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      onPopInvoked: (didPop) {
        if (_isSubmitting) return;
      },
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.cardSurface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          left: 20,
          right: 20,
          top: 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40, height: 4,
                  decoration: BoxDecoration(
                    color: AppTheme.navyBlue.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // Header
              Row(
                children: [
                  Icon(Icons.warning_rounded, color: AppTheme.brightNavy, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text('Report Incident',
                      style: TextStyle(color: AppTheme.navyBlue, fontSize: 20, fontWeight: FontWeight.bold)),
                  ),
                  IconButton(
                    onPressed: _isSubmitting ? null : () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: SojornColors.textDisabled),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Mini map — user taps to move the beacon pin.
              // Coordinates are shown fuzzed (~1 km) so users know what precision is shared.
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: SizedBox(
                  height: 150,
                  child: FlutterMap(
                    mapController: _mapController,
                    options: MapOptions(
                      initialCenter: LatLng(_pickedLat, _pickedLong),
                      initialZoom: 14,
                      onTap: (_, point) {
                        setState(() {
                          _pickedLat = point.latitude;
                          _pickedLong = point.longitude;
                        });
                      },
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.mpls.sojorn',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: LatLng(_pickedLat, _pickedLong),
                            width: 36,
                            height: 36,
                            child: Icon(Icons.location_pin, color: AppTheme.brightNavy, size: 36),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Tap map to move pin  •  ~${_pickedLat.toStringAsFixed(2)}, ~${_pickedLong.toStringAsFixed(2)}',
                style: TextStyle(color: SojornColors.textDisabled, fontSize: 11),
              ),
              const SizedBox(height: 16),

              // Incident type — horizontal scroll chips
              Text('What\'s happening?',
                style: TextStyle(color: AppTheme.navyBlue.withValues(alpha: 0.7), fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              SizedBox(
                height: 36,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: _types.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 8),
                  itemBuilder: (_, i) {
                    final type = _types[i];
                    final isSelected = type == _selectedType;
                    return GestureDetector(
                      onTap: () => setState(() => _selectedType = type),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? type.color.withValues(alpha: 0.12) : AppTheme.scaffoldBg,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: isSelected ? type.color : AppTheme.navyBlue.withValues(alpha: 0.1),
                            width: isSelected ? 1.5 : 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(type.icon, size: 14, color: isSelected ? type.color : SojornColors.postContentLight),
                            const SizedBox(width: 5),
                            Text(type.displayName,
                              style: TextStyle(
                                color: isSelected ? type.color : SojornColors.postContentLight,
                                fontSize: 12, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal)),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 16),

              // Severity selector
              Text('Severity',
                style: TextStyle(color: AppTheme.navyBlue.withValues(alpha: 0.7), fontSize: 13, fontWeight: FontWeight.w600)),
              const SizedBox(height: 10),
              Row(
                children: BeaconSeverity.values.map((sev) {
                  final isSelected = sev == _selectedSeverity;
                  return Expanded(
                    child: GestureDetector(
                      onTap: () => setState(() => _selectedSeverity = sev),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: isSelected ? sev.color.withValues(alpha: 0.12) : AppTheme.scaffoldBg,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: isSelected ? sev.color : AppTheme.navyBlue.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(sev.icon, size: 18, color: isSelected ? sev.color : SojornColors.textDisabled),
                            const SizedBox(height: 4),
                            Text(sev.label,
                              style: TextStyle(
                                color: isSelected ? sev.color : SojornColors.textDisabled,
                                fontSize: 10, fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 20),

              // Description
              TextFormField(
                controller: _descriptionController,
                style: TextStyle(color: SojornColors.postContent, fontSize: 14),
                decoration: InputDecoration(
                  hintText: _hintText,
                  hintStyle: TextStyle(color: SojornColors.textDisabled),
                  filled: true,
                  fillColor: AppTheme.scaffoldBg,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppTheme.navyBlue.withValues(alpha: 0.1)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppTheme.navyBlue.withValues(alpha: 0.1)),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppTheme.brightNavy, width: 1),
                  ),
                  counterStyle: TextStyle(color: SojornColors.textDisabled),
                ),
                maxLines: 3,
                maxLength: 300,
              ),
              const SizedBox(height: 12),

              // Photo
              if (_selectedImage != null) ...[
                Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.file(_selectedImage!, height: 120, width: double.infinity, fit: BoxFit.cover),
                    ),
                    Positioned(
                      top: 6, right: 6,
                      child: IconButton(
                        onPressed: _removeImage,
                        icon: const Icon(Icons.close, color: SojornColors.basicWhite, size: 18),
                        style: IconButton.styleFrom(backgroundColor: SojornColors.overlayDark, padding: const EdgeInsets.all(4)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ] else ...[
                GestureDetector(
                  onTap: _isUploadingImage ? null : _pickImage,
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: AppTheme.scaffoldBg,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppTheme.navyBlue.withValues(alpha: 0.1)),
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_isUploadingImage)
                          SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: AppTheme.brightNavy))
                        else
                          Icon(Icons.add_photo_alternate, size: 18, color: SojornColors.textDisabled),
                        const SizedBox(width: 8),
                        Text(_isUploadingImage ? 'Uploading...' : 'Add photo evidence',
                          style: TextStyle(color: SojornColors.textDisabled, fontSize: 13)),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // Submit button
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppTheme.brightNavy,
                    foregroundColor: SojornColors.basicWhite,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    disabledBackgroundColor: AppTheme.brightNavy.withValues(alpha: 0.3),
                  ),
                  child: _isSubmitting
                      ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: SojornColors.basicWhite))
                      : const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.warning_rounded, size: 18),
                            SizedBox(width: 8),
                            Text('Submit Report', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                          ],
                        ),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }
}

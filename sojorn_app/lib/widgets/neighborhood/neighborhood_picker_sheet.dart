// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../../services/api_service.dart';
import '../../theme/app_theme.dart';
import '../../theme/tokens.dart';

/// Full-screen bottom sheet for first-time neighborhood setup.
/// Shows GPS-suggested neighborhoods and a ZIP code search.
class NeighborhoodPickerSheet extends StatefulWidget {
  /// If true, show the "once per month" warning (from settings flow).
  final bool isChangeMode;
  /// Next allowed change date string (from backend).
  final String? nextChangeDate;

  const NeighborhoodPickerSheet({
    super.key,
    this.isChangeMode = false,
    this.nextChangeDate,
  });

  /// Returns the chosen neighborhood data Map, or null if dismissed.
  static Future<Map<String, dynamic>?> show(
    BuildContext context, {
    bool isChangeMode = false,
    String? nextChangeDate,
  }) {
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => NeighborhoodPickerSheet(
        isChangeMode: isChangeMode,
        nextChangeDate: nextChangeDate,
      ),
    );
  }

  @override
  State<NeighborhoodPickerSheet> createState() => _NeighborhoodPickerSheetState();
}

class _NeighborhoodPickerSheetState extends State<NeighborhoodPickerSheet> {
  final _zipController = TextEditingController();
  Timer? _debounce;

  bool _isLoadingGps = true;
  bool _isSearching = false;
  bool _isChoosing = false;

  List<Map<String, dynamic>> _gpsSuggestions = [];
  List<Map<String, dynamic>> _zipResults = [];
  String? _gpsError;
  String? _selectedId;

  @override
  void initState() {
    super.initState();
    _detectViaGps();
  }

  @override
  void dispose() {
    _zipController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _detectViaGps() async {
    setState(() {
      _isLoadingGps = true;
      _gpsError = null;
    });

    if (kIsWeb) {
      setState(() {
        _gpsError = 'GPS detection unavailable on web. Enter your ZIP code below.';
        _isLoadingGps = false;
      });
      return;
    }

    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.low, // "fuzzy" — faster + less battery
      );
      final data = await ApiService.instance.detectNeighborhood(
        lat: position.latitude,
        long: position.longitude,
      );
      if (!mounted) return;

      // The detect endpoint returns a single neighborhood; wrap it as a list
      final hood = data['neighborhood'] as Map<String, dynamic>?;
      if (hood != null) {
        // Also show nearby seeds via ZIP if we got a zip_code
        final zip = hood['zip_code'] as String? ?? '';
        List<Map<String, dynamic>> nearby = [];
        if (zip.isNotEmpty) {
          try {
            nearby = await ApiService.instance.searchNeighborhoodsByZip(zip);
          } catch (_) {}
        }

        setState(() {
          // Put the GPS-detected one first, then add ZIP-nearby ones (deduped)
          final detectedId = hood['id']?.toString() ?? '';
          _gpsSuggestions = [
            {...hood, '_detected': true},
            ...nearby.where((n) => n['id']?.toString() != detectedId),
          ];
          _isLoadingGps = false;
        });
      } else {
        setState(() {
          _gpsSuggestions = [];
          _isLoadingGps = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _gpsError = 'Could not determine your location. Enter your ZIP code below.';
          _isLoadingGps = false;
        });
      }
    }
  }

  void _onZipChanged(String value) {
    _debounce?.cancel();
    if (value.length < 3) {
      setState(() => _zipResults = []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () async {
      if (!mounted) return;
      setState(() => _isSearching = true);
      try {
        final results = await ApiService.instance.searchNeighborhoodsByZip(value);
        if (mounted) setState(() => _zipResults = results);
      } catch (_) {
        if (mounted) setState(() => _zipResults = []);
      } finally {
        if (mounted) setState(() => _isSearching = false);
      }
    });
  }

  Future<void> _chooseNeighborhood(Map<String, dynamic> hood) async {
    final id = hood['id']?.toString();
    if (id == null || id.isEmpty) return;

    setState(() {
      _isChoosing = true;
      _selectedId = id;
    });

    try {
      final result = await ApiService.instance.chooseNeighborhood(id);
      if (mounted) Navigator.of(context).pop(result);
    } catch (e) {
      if (mounted) {
        final errMsg = e.toString();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(errMsg.contains('once per month')
              ? 'You can only change your neighborhood once per month.'
              : 'Failed to set neighborhood. Try again.')),
        );
        setState(() {
          _isChoosing = false;
          _selectedId = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      decoration: BoxDecoration(
        color: AppTheme.scaffoldBg,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        boxShadow: [
          BoxShadow(
            color: AppTheme.navyBlue.withValues(alpha: 0.15),
            blurRadius: 30,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: AppTheme.navyBlue.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 4),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppTheme.brightNavy.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      widget.isChangeMode ? Icons.swap_horiz_rounded : Icons.location_city_rounded,
                      color: AppTheme.brightNavy,
                      size: 28,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    widget.isChangeMode ? 'Change Neighborhood' : 'Set Your Home Neighborhood',
                    style: AppTheme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.isChangeMode
                        ? 'You can change your neighborhood once every 30 days.'
                        : 'We\'ll show you local news, neighbors, and community boards.',
                    style: AppTheme.textTheme.bodySmall?.copyWith(
                      color: AppTheme.navyText.withValues(alpha: 0.6),
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (widget.isChangeMode && widget.nextChangeDate != null) ...[
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: SojornColors.nsfwWarningIcon.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '⏱ Next change allowed: ${_formatDate(widget.nextChangeDate!)}',
                        style: TextStyle(
                          color: SojornColors.nsfwWarningIcon,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 16),

            // ZIP Code input
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                decoration: BoxDecoration(
                  color: SojornColors.basicWhite.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppTheme.egyptianBlue.withValues(alpha: 0.15)),
                ),
                child: TextField(
                  controller: _zipController,
                  onChanged: _onZipChanged,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    hintText: 'Enter ZIP code to search...',
                    hintStyle: TextStyle(color: AppTheme.navyText.withValues(alpha: 0.35)),
                    prefixIcon: Icon(Icons.search, color: AppTheme.navyBlue.withValues(alpha: 0.5)),
                    suffixIcon: _isSearching
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                          )
                        : null,
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  ),
                ),
              ),
            ),

            const SizedBox(height: 16),

            // Results list
            Flexible(
              child: _buildResultsList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsList() {
    // Show ZIP results if searching, otherwise GPS suggestions
    final List<Map<String, dynamic>> items =
        _zipController.text.length >= 3 ? _zipResults : _gpsSuggestions;

    if (_isLoadingGps && _zipController.text.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 40,
              height: 40,
              child: CircularProgressIndicator(
                strokeWidth: 3,
                color: AppTheme.brightNavy,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Detecting your location...',
              style: TextStyle(
                color: AppTheme.navyText.withValues(alpha: 0.5),
                fontSize: 14,
              ),
            ),
          ],
        ),
      );
    }

    if (_gpsError != null && _zipController.text.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.location_off, color: AppTheme.navyText.withValues(alpha: 0.3), size: 36),
            const SizedBox(height: 12),
            Text(
              _gpsError!,
              style: TextStyle(color: AppTheme.navyText.withValues(alpha: 0.5), fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (items.isEmpty && _zipController.text.length >= 3 && !_isSearching) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, color: AppTheme.navyText.withValues(alpha: 0.3), size: 36),
            const SizedBox(height: 12),
            Text(
              'No neighborhoods found for "${_zipController.text}"',
              style: TextStyle(color: AppTheme.navyText.withValues(alpha: 0.5), fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      );
    }

    if (items.isEmpty) return const SizedBox.shrink();

    return ListView.separated(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      itemCount: items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        final hood = items[index];
        final isDetected = hood['_detected'] == true;
        final id = hood['id']?.toString() ?? '';
        final name = hood['name'] as String? ?? 'Unknown';
        final city = hood['city'] as String? ?? '';
        final state = hood['state'] as String? ?? '';
        final zip = hood['zip_code'] as String? ?? '';
        final isSelected = _selectedId == id;

        return GestureDetector(
          onTap: _isChoosing ? null : () => _chooseNeighborhood(hood),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected
                  ? AppTheme.brightNavy.withValues(alpha: 0.1)
                  : SojornColors.basicWhite.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? AppTheme.brightNavy.withValues(alpha: 0.4)
                    : isDetected
                        ? AppTheme.egyptianBlue.withValues(alpha: 0.25)
                        : AppTheme.egyptianBlue.withValues(alpha: 0.1),
                width: isSelected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: isDetected
                        ? AppTheme.egyptianBlue.withValues(alpha: 0.12)
                        : AppTheme.navyBlue.withValues(alpha: 0.06),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    isDetected ? Icons.my_location : Icons.location_on_outlined,
                    size: 20,
                    color: isDetected ? AppTheme.egyptianBlue : AppTheme.navyBlue.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              name,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 15,
                                color: AppTheme.navyBlue,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isDetected)
                            Container(
                              margin: const EdgeInsets.only(left: 6),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: AppTheme.egyptianBlue.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                'GPS',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  color: AppTheme.egyptianBlue,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [city, state, if (zip.isNotEmpty) zip].where((s) => s.isNotEmpty).join(', '),
                        style: TextStyle(
                          fontSize: 12,
                          color: AppTheme.navyText.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                if (isSelected && _isChoosing)
                  const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                else
                  Icon(
                    Icons.chevron_right,
                    color: AppTheme.navyBlue.withValues(alpha: 0.3),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDate(String isoDate) {
    try {
      final dt = DateTime.parse(isoDate);
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${months[dt.month - 1]} ${dt.day}, ${dt.year}';
    } catch (_) {
      return isoDate;
    }
  }
}

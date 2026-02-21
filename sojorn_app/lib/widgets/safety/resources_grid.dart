// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import '../../theme/tokens.dart';

/// Quick-action grid for community resources: Emergency Contacts, Shelters,
/// Power Outage Map, Report Hazard. Each button fires an onTap callback.
class ResourcesGrid extends StatelessWidget {
  final VoidCallback? onEmergencyContactsTap;
  final VoidCallback? onSheltersTap;
  final VoidCallback? onPowerOutageTap;
  final VoidCallback? onReportHazardTap;

  const ResourcesGrid({
    super.key,
    this.onEmergencyContactsTap,
    this.onSheltersTap,
    this.onPowerOutageTap,
    this.onReportHazardTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: 8),
            child: Text(
              'Community Resources',
              style: TextStyle(
                color: SojornColors.basicWhite.withValues(alpha: 0.7),
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Row(
            children: [
              Expanded(
                child: _ResourceButton(
                  icon: Icons.phone_in_talk,
                  label: 'Emergency\nContacts',
                  color: const Color(0xFFEF5350),
                  onTap: onEmergencyContactsTap,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ResourceButton(
                  icon: Icons.night_shelter,
                  label: 'Shelters',
                  color: const Color(0xFF42A5F5),
                  onTap: onSheltersTap,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ResourceButton(
                  icon: Icons.power_off,
                  label: 'Power\nOutage',
                  color: const Color(0xFFFFA726),
                  onTap: onPowerOutageTap,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _ResourceButton(
                  icon: Icons.warning_amber,
                  label: 'Report\nHazard',
                  color: const Color(0xFFFF7043),
                  onTap: onReportHazardTap,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ResourceButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  const _ResourceButton({
    required this.icon,
    required this.label,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 4),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 22),
            const SizedBox(height: 6),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: SojornColors.basicWhite.withValues(alpha: 0.7),
                fontSize: 10,
                fontWeight: FontWeight.w500,
                height: 1.2,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

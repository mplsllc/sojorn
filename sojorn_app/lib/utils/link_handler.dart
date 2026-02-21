// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';
import 'external_link_controller.dart';
import '../routes/app_routes.dart';

/// Utility for safely launching URLs and links.
///
/// Provides a clean interface for opening external links from anywhere
/// in the app, with automatic scheme detection and error handling.
///
/// NOTE: For external URLs, prefer using [ExternalLinkController.handleUrl]
/// which includes safety checks against the domain whitelist.
class LinkHandler {
  /// Launches a URL string, handling common edge cases.
  ///
  /// [context] - BuildContext for showing error SnackBars
  /// [url] - The URL to open (can be with or without scheme)
  ///
  /// If the URL doesn't have a scheme (http/https), https is assumed.
  /// Uses the [ExternalLinkController] for safety checks on external links.
  /// Handles sojorn:// deep links by navigating to the Beacon screen.
  static Future<void> launchLink(BuildContext context, String url) async {
    if (url.trim().isEmpty) return;

    // Handle sojorn:// deep links - navigate within app to Beacon screen
    if (url.startsWith('sojorn://')) {
      Uri? uri = Uri.tryParse(url.replaceFirst('sojorn://', 'sojorn://'));
      // Normalize to https for query parsing if needed
      uri ??=
          Uri.tryParse(url.replaceFirst('sojorn://', 'https://sojorn.net/'));

      final latParam = uri?.queryParameters['lat'];
      final longParam = uri?.queryParameters['long'];

      if (latParam != null && longParam != null) {
        final lat = double.tryParse(latParam);
        final long = double.tryParse(longParam);

        if (lat != null && long != null) {
          AppRoutes.navigateToBeacon(context, LatLng(lat, long));
          return;
        }
      }

      // If no valid coordinates, just open beacon screen at current/default
      AppRoutes.navigateToBeacon(context, LatLng(37.7749, -122.4194));
      return;
    }

    // Ensure scheme exists
    final Uri? uri = Uri.tryParse(url);
    final Uri effectiveUri;

    if (uri != null && !uri.hasScheme) {
      effectiveUri = Uri.parse('https://$url');
    } else {
      effectiveUri = uri ?? Uri.parse(url);
    }

    // Use ExternalLinkController for safety checks
    await ExternalLinkController.handleUrl(context, effectiveUri.toString());
  }

  /// Quick launcher for safe/trusted URLs without safety prompts.
  /// Use this only for URLs you know are safe.
  ///
  /// [context] - BuildContext for showing error SnackBars
  /// [url] - The URL to open
  static Future<void> launchSafeUrl(BuildContext context, String url) async {
    if (url.trim().isEmpty) return;

    final Uri? uri = Uri.tryParse(url);
    if (uri == null) return;

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
      } else {
        _showError(context, 'Could not open link.');
      }
    } catch (e) {
      _showError(context, 'Error opening link: $e');
    }
  }

  static void _showError(BuildContext context, String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

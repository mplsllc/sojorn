// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:js' as js;
import 'dart:ui_web' as ui_web;

import 'package:flutter/material.dart';

bool get webCameraPlayerSupported => true;

// Track registered view types so we never double-register.
final Set<String> _registeredViews = {};

/// Builds an inline HLS video player for Flutter web.
/// Uses HLS.js (must be loaded in index.html) for Chrome/Firefox,
/// and falls back to native <video> HLS support for Safari.
Widget buildInlineCameraPlayer(String streamUrl) {
  final viewType = 'hls-cam-${streamUrl.hashCode.abs()}';

  if (!_registeredViews.contains(viewType)) {
    _registeredViews.add(viewType);
    ui_web.platformViewRegistry.registerViewFactory(viewType, (int viewId) {
      final video = html.VideoElement()
        ..controls = true
        ..autoplay = true
        ..style.width = '100%'
        ..style.height = '100%'
        ..style.objectFit = 'contain'
        ..style.background = '#000'
        ..style.display = 'block';

      // Use HLS.js when available (Chrome, Firefox); native HLS for Safari.
      final hlsCtor = js.context['Hls'];
      if (hlsCtor != null) {
        final isSupported = hlsCtor.callMethod('isSupported') as bool? ?? false;
        if (isSupported) {
          final hls = js.JsObject(hlsCtor as js.JsFunction, []);
          hls.callMethod('loadSource', [streamUrl]);
          hls.callMethod('attachMedia', [video]);
        } else {
          // Safari native HLS
          video.src = streamUrl;
          video.load();
        }
      } else {
        video.src = streamUrl;
        video.load();
      }

      return video;
    });
  }

  return HtmlElementView(viewType: viewType);
}

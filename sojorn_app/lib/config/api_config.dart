// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

class ApiConfig {
  // Not const so we can normalize away accidentally-configured http/8080 URLs.
  static final String baseUrl = _computeBaseUrl();

  static String _computeBaseUrl() {
    String raw = const String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'https://api.sojorn.net/api/v1',
    );

    // Failsafe: migrate legacy domain if it slips in via environment or cache
    if (raw.contains('gosojorn.com')) {
      raw = raw.replaceAll('gosojorn.com', 'sojorn.net');
    }

    // Auto-upgrade any lingering http://api.sojorn.net:8080 (or plain http)
    // to the public https endpoint behind nginx.
    if (raw.startsWith('http://api.sojorn.net:8080')) {
      return raw.replaceFirst(
        'http://api.sojorn.net:8080',
        'https://api.sojorn.net',
      );
    }

    if (raw.startsWith('http://')) {
      return 'https://${raw.substring('http://'.length)}';
    }

    return raw;
  }

  /// Wraps external GIF/image URLs (Reddit, GifCities) through the server proxy
  /// so the client's IP is never sent to third-party origins.
  static String proxyImageUrl(String url) {
    return '$baseUrl/image-proxy?url=${Uri.encodeComponent(url)}';
  }

  /// Returns true if [url] is an external GIF that should be proxied.
  static bool needsProxy(String url) {
    return url.startsWith('https://i.redd.it/') ||
        url.startsWith('https://preview.redd.it/') ||
        url.startsWith('https://external-preview.redd.it/') ||
        url.startsWith('https://blob.gifcities.org/gifcities/') ||
        url.startsWith('https://i.imgur.com/') ||
        url.startsWith('https://media.giphy.com/');
  }
}

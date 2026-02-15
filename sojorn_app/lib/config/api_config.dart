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
}

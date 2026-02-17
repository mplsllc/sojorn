import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:connectivity_plus/connectivity_plus.dart';

/// Service for monitoring network connectivity status
class NetworkService {
  static final NetworkService _instance = NetworkService._internal();
  factory NetworkService() => _instance;
  NetworkService._internal();

  Connectivity? _connectivity;
  final StreamController<bool> _connectionController =
      StreamController<bool>.broadcast();

  Stream<bool> get connectionStream => _connectionController.stream;
  bool _isConnected = true;

  bool get isConnected => _isConnected;

  /// Initialize the network service and start monitoring
  void initialize() {
    // Skip connectivity monitoring on web - it's not supported
    if (kIsWeb) {
      _isConnected = true;
      _connectionController.add(true);
      return;
    }

    _connectivity = Connectivity();
    _connectivity!.onConnectivityChanged.listen((List<ConnectivityResult> results) {
      final result = results.isNotEmpty ? results.first : ConnectivityResult.none;
      _isConnected = result != ConnectivityResult.none;
      _connectionController.add(_isConnected);
    });

    // Check initial state
    _checkConnection();
  }

  Future<void> _checkConnection() async {
    if (kIsWeb || _connectivity == null) return;
    
    final results = await _connectivity!.checkConnectivity();
    final result = results.isNotEmpty ? results.first : ConnectivityResult.none;
    _isConnected = result != ConnectivityResult.none;
    _connectionController.add(_isConnected);
  }

  void dispose() {
    _connectionController.close();
  }
}

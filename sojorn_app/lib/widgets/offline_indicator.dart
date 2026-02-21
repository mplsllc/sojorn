// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter/material.dart';
import '../services/network_service.dart';

/// Banner that appears at top of screen when offline
class OfflineIndicator extends StatelessWidget {
  const OfflineIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<bool>(
      stream: NetworkService().connectionStream,
      initialData: NetworkService().isConnected,
      builder: (context, snapshot) {
        final isConnected = snapshot.data ?? true;

        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: isConnected ? 0 : 30,
          color: Colors.orange[700],
          child: !isConnected
              ? Center(
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.wifi_off, size: 16, color: Colors.white),
                      const SizedBox(width: 8),
                      Text(
                        'No internet connection',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                )
              : null,
        );
      },
    );
  }
}

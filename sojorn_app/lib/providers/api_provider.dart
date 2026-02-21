// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/api_service.dart';

import '../providers/auth_provider.dart';

final apiServiceProvider = Provider<ApiService>((ref) {
  final authService = ref.watch(authServiceProvider);
  return ApiService(authService);
});

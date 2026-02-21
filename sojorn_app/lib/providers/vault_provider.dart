// Copyright (c) 2026 MPLS LLC
// Licensed under the Apache License, Version 2.0
// See LICENSE file for details

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/key_vault_service.dart';

/// Provider that checks whether the encryption vault has been set up.
/// Returns true once the user has created a recovery passphrase.
final vaultSetupProvider = FutureProvider<bool>((ref) async {
  return await KeyVaultService.instance.isVaultSetup();
});

// Copyright (c) 2026 MPLS LLC
// Licensed under the GNU Affero General Public License v3.0 (AGPL-3.0)
// See LICENSE file in the project root for full license text.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/key_vault_service.dart';

/// Provider that checks whether the encryption vault has been set up.
/// Returns true once the user has created a recovery passphrase.
final vaultSetupProvider = FutureProvider<bool>((ref) async {
  return await KeyVaultService.instance.isVaultSetup();
});

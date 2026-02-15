import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/key_vault_service.dart';

/// Provider that checks whether the encryption vault has been set up.
/// Returns true once the user has created a recovery passphrase.
final vaultSetupProvider = FutureProvider<bool>((ref) async {
  return await KeyVaultService.instance.isVaultSetup();
});

// Run this once to clear cached Supabase session
// Instructions:
// 1. Run the Flutter app
// 2. In the app, navigate to sign in screen
// 3. BEFORE signing in, clear app data (or follow manual steps below)
//
// Manual clear on Android:
// Settings > Apps > sojorn > Storage > Clear Data
//
// Manual clear on iOS:
// Delete and reinstall the app
//
// Manual clear on Web/Desktop:
// Delete browser storage / app data folder

void main() {
  print('===================================');
  print('Clear Supabase Session Instructions');
  print('===================================');
  print('');
  print('The app has cached a session from a different Supabase project.');
  print('You need to clear the cached session.');
  print('');
  print('ON ANDROID:');
  print('  1. Go to Settings > Apps > sojorn');
  print('  2. Tap Storage');
  print('  3. Tap "Clear Data" or "Clear Storage"');
  print('  4. Restart the app');
  print('');
  print('ON WEB (Chrome):');
  print('  1. Open DevTools (F12)');
  print('  2. Go to Application tab');
  print('  3. Under Storage, click "Clear site data"');
  print('  4. Refresh the page');
  print('');
  print('OR: In the app, try to sign out if there\'s a sign out button.');
  print('');
}

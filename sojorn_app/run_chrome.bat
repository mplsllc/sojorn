@echo off
REM Run Sojorn on Chrome with environment variables

echo Starting Sojorn on Chrome...
echo.

flutter run -d chrome ^
  --web-renderer canvaskit ^
  --dart-define=API_BASE_URL=https://api.sojorn.net/api/v1 ^
  --dart-define-from-file=dart-defines.env

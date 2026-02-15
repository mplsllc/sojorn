@echo off
REM Run Sojorn on Chrome with environment variables

echo Starting Sojorn on Chrome...
echo.

flutter run -d chrome ^
  --dart-define=API_BASE_URL=https://api.sojorn.net/api/v1

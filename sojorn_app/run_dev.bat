@echo off
REM Run Sojorn in development mode with environment variables

echo Starting Sojorn in development mode...
echo.

flutter run ^
  --dart-define=API_BASE_URL=https://api.sojorn.net/api/v1

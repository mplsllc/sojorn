@echo off
echo Deploying create-beacon edge function to Supabase...
echo.

supabase functions deploy create-beacon --no-verify-jwt

echo.
echo Deployment complete!
echo.
echo The beacon feature should now work properly.
echo Test by opening the Beacon tab in the app and creating a beacon.
pause

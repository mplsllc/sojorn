@echo off
echo Updating reaction configuration...
echo.

cd /d "%~dp0.."

dart tools\generate_reaction_config.dart

echo.
echo ✅ Reaction configuration updated!
echo 📁 Make sure to restart your app to see changes
echo.
pause

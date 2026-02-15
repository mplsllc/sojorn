@echo off
echo Adding new reaction folders to reaction picker...
echo.

cd /d "%~dp0.."

dart tools\add_reaction_folder.dart

echo.
echo ✅ Reaction picker updated!
echo 🔄 Restart your app to see the new reaction tabs
echo.
pause

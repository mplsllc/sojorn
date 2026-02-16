# Deploy all Edge Functions to Supabase
# Run this after updating supabase-js version

Write-Host "=== Deploying All Edge Functions ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "This will deploy all functions with --no-verify-jwt (default for this script)" -ForegroundColor Yellow
Write-Host ""

$functions = @(
    "appreciate",
    "block",
    "deactivate-account",
    "delete-account",
    "feed-personal",
    "feed-sojorn",
    "follow",
    "manage-post",
    "notifications",
    "profile",
    "profile-posts",
    "publish-comment",
    "publish-post",
    "push-notification",
    "report",
    "save",
    "search",
    "sign-media",
    "signup",
    "tone-check",
    "trending",
    "upload-image"
)

$totalFunctions = $functions.Count
$currentFunction = 0
$noVerifyJwt = "--no-verify-jwt"

foreach ($func in $functions) {
    $currentFunction++
    Write-Host "[$currentFunction/$totalFunctions] Deploying $func..." -ForegroundColor Yellow

    try {
        supabase functions deploy $func $noVerifyJwt 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Host "  OK $func deployed successfully" -ForegroundColor Green
        } else {
            Write-Host "  FAILED to deploy $func" -ForegroundColor Red
        }
    }
    catch {
        Write-Host "  ERROR deploying $func : $_" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "=== Deployment Complete ===" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Restart your Flutter app" -ForegroundColor Yellow
Write-Host "2. Sign in again" -ForegroundColor Yellow
Write-Host "3. The JWT 401 errors should be gone!" -ForegroundColor Green
Write-Host ""

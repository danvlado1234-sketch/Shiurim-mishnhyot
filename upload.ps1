# עטיפה: קוד ההעלאה נמצא בריפו הפרטי, ב-..\סקריפטים\upload-mishna.ps1 (מ-26.11.2026).
# הפרמטרים מוצהרים כאן במפורש ועוברים כמו שהם; קוד היציאה חוזר כמו שהוא.
# פרמטר חדש ב-upload-mishna.ps1 — להוסיף גם כאן (בלעדיו העטיפה תסרב לו בשגיאה, לא בשקט).
param([switch]$Backlog, [switch]$AllowShrink, [switch]$Pause)
$target = Join-Path (Split-Path $PSScriptRoot -Parent) 'סקריפטים\upload-mishna.ps1'
if (-not (Test-Path -LiteralPath $target)) {
    Write-Host "!! לא נמצא קוד ההעלאה: $target" -ForegroundColor Red
    if ($Pause) { Read-Host 'לחץ Enter לסגירה' | Out-Null }
    exit 1
}
& $target -RepoDir $PSScriptRoot @PSBoundParameters
exit $LASTEXITCODE
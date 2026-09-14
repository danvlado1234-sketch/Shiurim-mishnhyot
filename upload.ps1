# ============================================================
#  העלאת שיעורים - סקריפט אוטומטי מלא
#  עושה הכל בפקודה אחת:
#   1. מעלה את כל השיעורים ל-R2 (רק חדשים/משתנים)
#   2. מייצר list.json מעודכן
#   3. דוחף list.json ל-GitHub
#
#  שימוש: קליק ימני -> Run with PowerShell
#         או:  powershell -ExecutionPolicy Bypass -File .\upload.ps1
# ============================================================

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
Set-Location $root

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "     העלאת שיעורים - תהליך אוטומטי" -ForegroundColor Cyan
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

# ---- תיקון אוטומטי לשמות קבצים ----
# וואטסאפ שומר הודעות קוליות בתור .mp4 (קונטיינר שמע, לא וידאו), ולא .m4a.
# בודקים בתוך הקובץ (לא רק לפי הסיומת) שאין בו track וידאו לפני שנוגעים בו -
# כדי שלעולם לא ישונה בטעות קובץ וידאו אמיתי שהגיע לכאן בטעות.
function Test-IsAudioOnlyMp4 {
    param([string]$Path)
    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $text = [System.Text.Encoding]::GetEncoding('ISO-8859-1').GetString($bytes)
        $hasVideo = $false; $hasAudio = $false
        $idx = 0
        while ($true) {
            $idx = $text.IndexOf('hdlr', $idx)
            if ($idx -lt 0) { break }
            if ($idx + 16 -le $text.Length) {
                $type = $text.Substring($idx + 12, 4)
                if ($type -eq 'vide') { $hasVideo = $true }
                if ($type -eq 'soun') { $hasAudio = $true }
            }
            $idx += 4
        }
        return ($hasAudio -and -not $hasVideo)
    } catch { return $false }
}

$mp4Files = Get-ChildItem -Path $root -Recurse -File -Filter '*.mp4' |
    Where-Object { $_.FullName -notmatch '\\\.git\\' }
$spacedFiles = Get-ChildItem -Path $root -Recurse -File |
    Where-Object { $_.Extension -match '^\.(m4a|mp3)$' -and $_.Name -match ' ' -and $_.FullName -notmatch '\\\.git\\' }

if ($mp4Files -or $spacedFiles) {
    Write-Host "[0/3] מתקן שמות קבצים (וואטסאפ / רווחים)..." -ForegroundColor Yellow

    # mp4 מוואטסאפ: קודם בודקים שהוא שמע בלבד, ואז מתקנים סיומת + רווחים ביחד
    foreach ($f in $mp4Files) {
        if (Test-IsAudioOnlyMp4 -Path $f.FullName) {
            $newName = ($f.BaseName -replace ' ', '_') + '.m4a'
            $newPath = Join-Path $f.DirectoryName $newName
            if (Test-Path $newPath) {
                Write-Host "      !! $($f.Name) - כבר קיים קובץ בשם $newName, לא הוחלף (בדקו ידנית)" -ForegroundColor Red
            } else {
                Rename-Item -Path $f.FullName -NewName $newName
                Write-Host "      תוקן: $($f.Name) -> $newName" -ForegroundColor Green
            }
        } else {
            Write-Host "      !! $($f.Name) נראה כקובץ וידאו אמיתי - לא נגעתי בו, בדקו ידנית" -ForegroundColor Red
        }
    }

    # m4a/mp3 עם רווחים בשם (למשל קובץ שהגיע במייל או הוקלד ידנית) - רק מחליפים רווחים
    foreach ($f in $spacedFiles) {
        $newName = $f.Name -replace ' ', '_'
        $newPath = Join-Path $f.DirectoryName $newName
        if (Test-Path $newPath) {
            Write-Host "      !! $($f.Name) - כבר קיים קובץ בשם $newName, לא הוחלף (בדקו ידנית)" -ForegroundColor Red
        } else {
            Rename-Item -Path $f.FullName -NewName $newName
            Write-Host "      תוקן: $($f.Name) -> $newName" -ForegroundColor Green
        }
    }

    Write-Host ""
}

# ---- שלב 1: העלאה ל-R2 ----
Write-Host "[1/3] מעלה שיעורים ל-R2..." -ForegroundColor Yellow
$masechtot = Get-ChildItem -Path $root -Directory | Where-Object { $_.Name -notmatch '^\.' }
foreach ($m in $masechtot) {
    Write-Host ("      -> " + $m.Name)
    & "$root\rclone.exe" copy "$($m.FullName)" "r2:shiurim/$($m.Name)" --transfers 8 --checkers 8
    if ($LASTEXITCODE -ne 0) { Write-Host "      !! שגיאה בהעלאת $($m.Name)" -ForegroundColor Red }
}
Write-Host "      העלאה ל-R2 הושלמה." -ForegroundColor Green
Write-Host ""

# ---- שלב 2: יצירת list.json ----
Write-Host "[2/3] מייצר list.json..." -ForegroundColor Yellow
$files = Get-ChildItem -Path $root -Recurse -File |
    Where-Object { $_.Extension -match '^\.(m4a|mp3)$' } |
    ForEach-Object { $_.FullName.Substring($root.Length + 1) -replace '\\', '/' } |
    Sort-Object
$json = ConvertTo-Json @($files) -Depth 1
[System.IO.File]::WriteAllText((Join-Path $root 'list.json'), $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("      list.json נוצר עם " + $files.Count + " שיעורים.") -ForegroundColor Green
Write-Host ""

# ---- שלב 3: דחיפה ל-GitHub ----
Write-Host "[3/3] דוחף list.json ל-GitHub..." -ForegroundColor Yellow
git add list.json index.html 2>$null
$changes = git status --porcelain
if ($changes) {
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm"
    git commit -m "עדכון שיעורים $stamp" | Out-Null
    git push origin HEAD:main
    if ($LASTEXITCODE -eq 0) {
        Write-Host "      נדחף ל-GitHub בהצלחה!" -ForegroundColor Green
    } else {
        Write-Host "      !! שגיאה בדחיפה ל-GitHub" -ForegroundColor Red
    }
} else {
    Write-Host "      אין שינויים חדשים ל-GitHub." -ForegroundColor Green
}

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "              הכל הושלם!" -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""
Read-Host "לחץ Enter לסגירה"

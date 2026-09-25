# ============================================================
#  העלאת שיעורי משנה - סקריפט אוטומטי מלא
#  עושה הכל בפקודה אחת:
#   0. מושך עדכונים מ-GitHub, מתקן ובודק שמות קבצים
#   1. מעלה את כל השיעורים ל-R2 (רק חדשים/משתנים)
#   2. מייצר list.json + רושם תאריך העלאה לשיעורים חדשים (uploads.json)
#   3. דוחף ל-GitHub
#
#  שימוש: "העלה שיעורים.bat"
#         או:  powershell -ExecutionPolicy Bypass -File .\upload.ps1
#  עם -Backlog ("העלה השלמות.bat"): אותו דבר, בלי רישום תאריך העלאה -
#  להשלמת שיעורים ישנים, כדי שלא יופיעו באתר ב"חדש השבוע"
#  ולא יזיזו את "השיעור עכשיו" (שנקבע לפי השיעור האחרון שעלה).
# ============================================================
param([switch]$Backlog)

$ErrorActionPreference = "Stop"
$root = $PSScriptRoot
if (-not $root) { $root = (Get-Location).Path }
Set-Location $root

Write-Host ""
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "     העלאת שיעורים - תהליך אוטומטי" -ForegroundColor Cyan
if ($Backlog) { Write-Host "     (השלמות - בלי רישום ב'חדש השבוע')" -ForegroundColor Cyan }
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host ""

# ---- משיכת עדכונים מ-GitHub (נוסף ספטמבר 2026) ----
# אחרי שינוי שנעשה ישירות ב-GitHub (עריכה באתר או מיזוג PR), הדחיפה בשלב 3
# נדחית ("rejected - fetch first") והאתר לא מתעדכן. לכן מושכים בתחילת כל
# הרצה, לפני שנוגעים בכלום. קבצי השמע חסומים ב-.gitignore, אז זה לא נוגע בהם.
# אם המשיכה נכשלת (אין אינטרנט, התנגשות) - מבטלים מיזוג חלקי, מדווחים וממשיכים:
# ההעלאה לענן לא תלויה בזה.
Write-Host "[0/3] מושך עדכונים מ-GitHub..." -ForegroundColor Yellow
git pull origin main --no-rebase --no-edit
if ($LASTEXITCODE -eq 0) {
    Write-Host "      מעודכן." -ForegroundColor Green
} else {
    # רק אם באמת נשאר מיזוג חלקי (בלי 2>$null: ב-PowerShell 5 עם Stop, פלט
    # שגיאה מופנה של git עוצר את כל הסקריפט)
    if (Test-Path (Join-Path $root '.git\MERGE_HEAD')) { git merge --abort }
    Write-Host "      !! המשיכה מ-GitHub נכשלה - ממשיך בכל זאת (ייתכן שהפרסום באתר ייכשל)" -ForegroundColor Red
}
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
# גרשיים/גרש בשם (למשל משנה_י"א במקום משנה_יא) - האתר לא מזהה אותם
$quoteChars = '["''׳״]'
$badNameFiles = Get-ChildItem -Path $root -Recurse -File |
    Where-Object { $_.Extension -match '^\.(m4a|mp3)$' -and ($_.Name -match ' ' -or $_.BaseName -match $quoteChars) -and $_.FullName -notmatch '\\\.git\\' }

if ($mp4Files -or $badNameFiles) {
    Write-Host "      מתקן שמות קבצים (וואטסאפ / רווחים / גרשיים)..." -ForegroundColor Yellow

    # mp4 מוואטסאפ: קודם בודקים שהוא שמע בלבד, ואז מתקנים סיומת
    foreach ($f in $mp4Files) {
        if (Test-IsAudioOnlyMp4 -Path $f.FullName) {
            $newName = $f.BaseName + '.m4a'
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

    # m4a/mp3 עם רווחים ו/או גרשיים בשם (קובץ שהגיע במייל, הוקלד ידנית, או mp4
    # שתוקן כאן למעלה) - מחליפים רווחים בקו תחתון ומוחקים גרשיים.
    $toClean = @(Get-ChildItem -Path $root -Recurse -File |
        Where-Object { $_.Extension -match '^\.(m4a|mp3)$' -and ($_.Name -match ' ' -or $_.BaseName -match $quoteChars) -and $_.FullName -notmatch '\\\.git\\' })
    foreach ($f in $toClean) {
        $newName = (($f.BaseName -replace ' ', '_') -replace $quoteChars, '') + $f.Extension
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

$masechtot = Get-ChildItem -Path $root -Directory | Where-Object { $_.Name -notmatch '^\.' }

# ---- בדיקת שמות קבצים (נוסף ספטמבר 2026) ----
# קובץ ששמו לא תקין עולה לענן ונכנס לרשימה, אבל האתר לא יודע לשייך אותו
# למסכת/פרק/משנה - והוא נדחק ל"שיעורים נוספים" בתחתית הדף. כאן בודקים מראש,
# באותו פענוח כמו parseFilename ב-index.html, ומזהירים. לא עוצרים את ההעלאה
# ולא משנים שמות לבד - רק מתריעים, עם הצעה לשם הנכון.
# הרשימה חייבת להיות זהה ל-SEDARIM ול-PEREK_COUNTS ב-index.html.
$PEREK_COUNTS = [ordered]@{
    'ברכות'=9;'פאה'=8;'דמאי'=7;'כלאים'=9;'שביעית'=10;'תרומות'=11;'מעשרות'=5;'מעשר שני'=5;'חלה'=4;'ערלה'=3;'ביכורים'=4
    'שבת'=24;'עירובין'=10;'פסחים'=10;'שקלים'=8;'יומא'=8;'סוכה'=5;'ביצה'=5;'ראש השנה'=4;'תענית'=4;'מגילה'=4;'מועד קטן'=3;'חגיגה'=3
    'יבמות'=16;'כתובות'=13;'נדרים'=11;'נזיר'=9;'סוטה'=9;'גיטין'=9;'קידושין'=4
    'בבא קמא'=10;'בבא מציעא'=10;'בבא בתרא'=10;'סנהדרין'=11;'מכות'=3;'שבועות'=8;'עדיות'=8;'עבודה זרה'=5;'אבות'=6;'הוריות'=3
    'זבחים'=14;'מנחות'=13;'חולין'=12;'בכורות'=9;'ערכין'=9;'תמורה'=7;'כריתות'=6;'מעילה'=6;'תמיד'=7;'מידות'=5;'קינים'=3
    'כלים'=30;'אהלות'=18;'נגעים'=14;'פרה'=12;'טהרות'=10;'מקוואות'=10;'נדה'=10;'מכשירין'=6;'זבים'=5;'טבול יום'=4;'ידים'=4;'עוקצין'=3
}
# ערכי הגימטריה. לא hash literal (@{...}): ב-PowerShell 5 של Windows המפתחות
# לא רגישים לאותיות סופיות, ו-'ך' נחשב כפילות של 'כ' - הסקריפט לא נטען.
# לכן מילון עם השוואה מדויקת (Ordinal), שנבנה מרשימה.
$GEM = New-Object 'System.Collections.Generic.Dictionary[string,int]' ([StringComparer]::Ordinal)
$gemLetters = 'אבגדהוזחטיכלמנסעפצקרשתךםןףץ'
$gemValues = @(1,2,3,4,5,6,7,8,9,10,20,30,40,50,60,70,80,90,100,200,300,400,20,40,50,80,90)
for ($gi = 0; $gi -lt $gemLetters.Length; $gi++) { $GEM[[string]$gemLetters[$gi]] = $gemValues[$gi] }
function Get-HebNum([string]$t) {
    if ($t -match '^\d+$') { return [int]$t }
    $sum = 0
    foreach ($ch in $t.ToCharArray()) { $k = [string]$ch; if (-not $GEM.ContainsKey($k)) { return 0 }; $sum += $GEM[$k] }
    return $sum
}
function Get-Plain([string]$s) { return (($s -replace '[֑-ׇ]', '') -replace '\s', '') }
function Find-Masechet([string]$name) {
    $n = Get-Plain $name
    foreach ($m in $PEREK_COUNTS.Keys) { if ((Get-Plain $m) -eq $n) { return $m } }
    return $null
}
# מרחק עריכה (כמה אותיות שונות) - להצעת "האם התכוונת ל..."
function Get-EditDistance([string]$a, [string]$b) {
    # טבלה חד-ממדית ($d[i * w + j]) - PowerShell 5 של Windows לא מצליח לפענח
    # אינדקס דו-ממדי ($d[$i, $j]) בתוך קריאה ל-[Math]::Min
    $w = $b.Length + 1
    $d = New-Object 'int[]' (($a.Length + 1) * $w)
    for ($i = 0; $i -le $a.Length; $i++) { $d[$i * $w] = $i }
    for ($j = 0; $j -le $b.Length; $j++) { $d[$j] = $j }
    for ($i = 1; $i -le $a.Length; $i++) {
        for ($j = 1; $j -le $b.Length; $j++) {
            $cost = if ($a[$i - 1] -eq $b[$j - 1]) { 0 } else { 1 }
            $del = $d[($i - 1) * $w + $j] + 1
            $ins = $d[$i * $w + $j - 1] + 1
            $sub = $d[($i - 1) * $w + $j - 1] + $cost
            $d[$i * $w + $j] = [Math]::Min([Math]::Min($del, $ins), $sub)
        }
    }
    return $d[$a.Length * $w + $b.Length]
}
# מפענח שם קובץ כמו האתר. מחזיר @{ ok; key; warn; why }
function Test-MishnaName([string]$fileName) {
    $base = ($fileName -replace '\.(mp3|m4a)$', '') -replace '^_+|_+$', ''
    $t = @($base -split '_' | Where-Object { $_ })
    $iP = [array]::IndexOf($t, 'פרק'); $iM = [array]::IndexOf($t, 'משנה')
    if ($iP -gt 0 -and $iM -gt $iP -and $iM + 1 -lt $t.Count) {
        $name = $t[0..($iP - 1)] -join ' '
        $m = Find-Masechet $name
        if (-not $m) {
            $plain = $name -replace '^מסכת ', ''
            if (Find-Masechet $plain) { return @{ ok = $false; why = "יש להשמיט את המילה 'מסכת' מתחילת השם (צריך למשל: $($plain -replace ' ', '_')_פרק_א_משנה_א)" } }
            $best = $null; $bestD = 99
            foreach ($v in $PEREK_COUNTS.Keys) { $dist = Get-EditDistance $name $v; if ($dist -lt $bestD) { $bestD = $dist; $best = $v } }
            $hint = if ($bestD -le 2) { " - האם התכוונת ל'$best'?" } else { '' }
            return @{ ok = $false; why = "שם המסכת '$name' לא מזוהה$hint" }
        }
        $perek = if ($iP + 1 -lt $iM) { Get-HebNum $t[$iP + 1] } else { 0 }
        if (-not $perek) { return @{ ok = $false; why = 'מספר הפרק לא מזוהה (צריך אותיות, למשל: פרק_יא)' } }
        $pieces = @(($t[($iM + 1)..($t.Count - 1)] -join '_') -split '[,\-_]+' | Where-Object { $_.Trim() })
        $nums = @()
        foreach ($p in $pieces) {
            $v = Get-HebNum $p.Trim()
            if (-not $v) { return @{ ok = $false; why = "מספר המשנה '$p' לא מזוהה (צריך אותיות, למשל: משנה_יא, או משנה_ג,_ד למשניות מאוחדות)" } }
            $nums += $v
        }
        $warn = ''
        if ($perek -gt $PEREK_COUNTS[$m]) { $warn = "במסכת $m יש רק $($PEREK_COUNTS[$m]) פרקים - לבדוק את מספר הפרק" }
        return @{ ok = $true; key = "$m|$perek|$($nums -join ',')"; warn = $warn }
    }
    # פורמט ישן: מסכת_1_11 (עם או בלי תאריך בסוף)
    $iN = -1
    for ($i = 0; $i -lt $t.Count; $i++) { if ($t[$i] -match '^\d+$') { $iN = $i; break } }
    if ($iN -gt 0 -and $iN + 1 -lt $t.Count -and $t[$iN + 1] -match '^\d+$') {
        $m = Find-Masechet ($t[0..($iN - 1)] -join ' ')
        if ($m) { return @{ ok = $true; key = "$m|$([int]$t[$iN])|$([int]$t[$iN + 1])"; warn = '' } }
    }
    return @{ ok = $false; why = 'השם לא בפורמט המוכר (צריך למשל: ברכות_פרק_א_משנה_ב)' }
}

$nameProblems = New-Object System.Collections.Generic.List[string]
$seenKeys = @{}
foreach ($f in (Get-ChildItem -Path $root -File | Where-Object { $_.Extension -match '^\.(m4a|mp3)$' })) {
    $nameProblems.Add("$($f.Name) נמצא בתיקייה הראשית ולא יעלה - להעביר לתיקיית המסכת")
}
foreach ($m in $masechtot) {
    foreach ($f in (Get-ChildItem -Path $m.FullName -Recurse -File | Where-Object { $_.Extension -match '^\.(m4a|mp3)$' })) {
        $rel = $f.FullName.Substring($root.Length + 1) -replace '\\', '/'
        $r = Test-MishnaName $f.Name
        if (-not $r.ok) { $nameProblems.Add("$rel - לא ישויך למשנה באתר: $($r.why)"); continue }
        if ($r.warn) { $nameProblems.Add("$rel - $($r.warn)") }
        if ($seenKeys.ContainsKey($r.key)) { $nameProblems.Add("$rel ו-$($seenKeys[$r.key]) הם אותה משנה - יופיעו באתר פעמיים") }
        else { $seenKeys[$r.key] = $rel }
    }
}
if ($nameProblems.Count -gt 0) {
    Write-Host "!! בעיות בשמות קבצים ($($nameProblems.Count)):" -ForegroundColor Red
    foreach ($msg in $nameProblems) { Write-Host "   - $msg" -ForegroundColor Red }
    Write-Host "   ההעלאה ממשיכה; אחרי תיקון השם - להריץ שוב." -ForegroundColor Red
    Write-Host ""
}

# ---- זיהוי שיעורים חדשים (לפני ש-list.json נכתב מחדש) ----
# קוראים עם קידוד UTF-8 מפורש: list.json נשמר בכוונה בלי BOM (כדי שהאתר יקרא
# אותו תקין), ובלי קידוד מפורש PowerShell מפרש את העברית לא נכון.
$listJsonPath = Join-Path $root 'list.json'
$oldFiles = @()
if (Test-Path $listJsonPath) {
    try {
        $rawOld = [System.IO.File]::ReadAllText($listJsonPath, [System.Text.Encoding]::UTF8)
        $oldFiles = @([regex]::Matches($rawOld, '"((?:[^"\\]|\\.)*)"') | ForEach-Object { $_.Groups[1].Value })
    } catch { $oldFiles = @() }
}

# רק קבצים בתוך תיקיות המסכתות - בדיוק מה שעולה לענן בשלב 1
$files = @()
foreach ($m in $masechtot) {
    Get-ChildItem -Path $m.FullName -Recurse -File |
        Where-Object { $_.Extension -match '^\.(m4a|mp3)$' } |
        ForEach-Object { $files += ($_.FullName.Substring($root.Length + 1) -replace '\\', '/') }
}
$files = @($files | Sort-Object)
$newFiles = @($files | Where-Object { $oldFiles -notcontains $_ })

# ---- שלב 1: העלאה ל-R2 ----
Write-Host "[1/3] מעלה שיעורים ל-R2..." -ForegroundColor Yellow
foreach ($m in $masechtot) {
    Write-Host ("      -> " + $m.Name)
    & "$root\rclone.exe" copy "$($m.FullName)" "r2:shiurim/$($m.Name)" --transfers 8 --checkers 8
    if ($LASTEXITCODE -ne 0) { Write-Host "      !! שגיאה בהעלאת $($m.Name)" -ForegroundColor Red }
}
Write-Host "      העלאה ל-R2 הושלמה." -ForegroundColor Green
Write-Host ""

# ---- שלב 2: יצירת list.json + uploads.json ----
Write-Host "[2/3] מייצר list.json..." -ForegroundColor Yellow
$json = ConvertTo-Json @($files) -Depth 1
[System.IO.File]::WriteAllText($listJsonPath, $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ("      list.json נוצר עם " + $files.Count + " שיעורים.") -ForegroundColor Green

# תאריך העלאה לכל שיעור חדש (uploads.json) - ממנו האתר יודע מה "השיעור עכשיו"
# (המשנה האחרונה שעלתה) ומה נכנס ל"חדש השבוע".
# בהעלאת השלמות (-Backlog) לא רושמים, כדי ששיעורים ישנים לא יופיעו כחדשים.
$uploadsPath = Join-Path $root 'uploads.json'
$uploads = [ordered]@{}
if (Test-Path $uploadsPath) {
    try {
        $rawUploads = [System.IO.File]::ReadAllText($uploadsPath, [System.Text.Encoding]::UTF8)
        foreach ($um in [regex]::Matches($rawUploads, '"((?:[^"\\]|\\.)*)"\s*:\s*"(\d{4}-\d{2}-\d{2})"')) {
            $uploads[$um.Groups[1].Value] = $um.Groups[2].Value
        }
    } catch { $uploads = [ordered]@{} }
}
if ($newFiles.Count -gt 0) {
    if ($Backlog) {
        Write-Host ("      " + $newFiles.Count + " שיעורים נוספו כהשלמות (בלי תאריך העלאה).") -ForegroundColor Green
    } else {
        $today = Get-Date -Format "yyyy-MM-dd"
        foreach ($f in $newFiles) { $uploads[$f] = $today }
        Write-Host ("      " + $newFiles.Count + " שיעורים חדשים נרשמו עם תאריך היום.") -ForegroundColor Green
    }
}
$uploadsJson = if ($uploads.Count) { $uploads | ConvertTo-Json -Depth 2 } else { '{}' }
[System.IO.File]::WriteAllText($uploadsPath, $uploadsJson, (New-Object System.Text.UTF8Encoding($false)))
Write-Host ""

# ---- שלב 3: דחיפה ל-GitHub ----
Write-Host "[3/3] דוחף ל-GitHub..." -ForegroundColor Yellow
git add list.json uploads.json index.html 2>$null
$changes = git status --porcelain list.json uploads.json index.html
if ($changes) {
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm"
    git commit -m "עדכון שיעורים $stamp" | Out-Null
    git push origin HEAD:main
    if ($LASTEXITCODE -eq 0) {
        Write-Host "      נדחף ל-GitHub בהצלחה!" -ForegroundColor Green
    } else {
        Write-Host "      !! שגיאה בדחיפה ל-GitHub. לתיקון להריץ כאן:" -ForegroundColor Red
        Write-Host "         git pull origin main --no-rebase --no-edit" -ForegroundColor Red
        Write-Host "         git push origin HEAD:main" -ForegroundColor Red
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

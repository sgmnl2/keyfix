# =============================================================================
#  Залипла клавіша — вимкнути через реєстр (Scancode Map)
#  Кодування файлу: UTF-8 з BOM
#
#  Чому реєстр, а не AHK: Scancode Map живе в драйвері класу клавіатури, тобто
#  спрацьовує до розкладок, до вікон і до входу в систему. Програма-перехоплювач
#  натомість стартує лише після входу, мовчить у вікнах із правами адміністратора
#  і гине разом зі своїм процесом.
#
#  Параметр у системі ОДИН на всю клавіатуру, тому всі правила пишуться в нього
#  разом. Через це пункт «вимкнути + перенести» — одна дія, а не дві поспіль.
# =============================================================================
$ErrorActionPreference = 'Stop'
$RegPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout'

# Скан-коди набору 1. Розширені (з префіксом E0) записані як 0xE0xx.
$KNOWN = [ordered]@{
    0x56   = 'додаткова клавіша між лівим Shift і Z (на ній ґ)'
    0x2B   = 'клавіша \ біля Enter'
    0x28   = "клавіша ' (на ній є)"
    0x1A   = 'клавіша [ (на ній х)'
    0x1B   = 'клавіша ] (на ній ї)'
    0x27   = 'клавіша ; (на ній ж)'
    0x3A   = 'Caps Lock'
    0xE05D = 'клавіша «Меню»'
    0xE05C = 'правий Win'
    0xE01D = 'правий Ctrl'
    0xE038 = 'правий Alt (AltGr)'
}

function Name-Of([int]$sc) {
    if ($KNOWN.Contains($sc)) { return $KNOWN[$sc] }
    return 'невідома клавіша'
}

function Show-Hex($bytes) { ($bytes | ForEach-Object { '{0:X2}' -f $_ }) -join ' ' }

# Карта: заголовок (8 нулів), кількість записів разом із кінцевиком,
# потім по 4 байти на правило — спершу КУДИ, далі ЗВІДКИ, обидва по 2 байти.
function Build-Map([object[]]$rules) {
    $m = [System.Collections.Generic.List[byte]]::new()
    $m.AddRange([byte[]]@(0,0,0,0, 0,0,0,0))
    $m.AddRange([BitConverter]::GetBytes([uint32]($rules.Count + 1)))
    foreach ($r in $rules) {
        $m.AddRange([byte[]]@(
            ($r.to   -band 0xFF), (($r.to   -shr 8) -band 0xFF),
            ($r.from -band 0xFF), (($r.from -shr 8) -band 0xFF)
        ))
    }
    $m.AddRange([byte[]]@(0,0,0,0))
    return ,$m.ToArray()
}

function Show-Current {
    $v = $null
    try { $v = (Get-ItemProperty -Path $RegPath -Name 'Scancode Map' -ErrorAction Stop).'Scancode Map' } catch { }
    Write-Host ''
    if (-not $v) {
        Write-Host '  Зараз: перевизначень немає, клавіатура в заводському стані.' -ForegroundColor Green
        return
    }
    $n = [BitConverter]::ToUInt32($v, 8) - 1
    Write-Host "  Зараз перевизначено клавіш: $n" -ForegroundColor Yellow
    for ($i = 0; $i -lt $n; $i++) {
        $o    = 12 + $i * 4
        $to   = [BitConverter]::ToUInt16($v, $o)
        $from = [BitConverter]::ToUInt16($v, $o + 2)
        if ($to -eq 0) { Write-Host ("    0x{0:X2} — вимкнено   ({1})" -f $from, (Name-Of $from)) }
        else           { Write-Host ("    0x{0:X2} -> 0x{1:X2}   ({2} -> {3})" -f $from, $to, (Name-Of $from), (Name-Of $to)) }
    }
}

function Write-Map([object[]]$rules) {
    $m = Build-Map $rules
    New-ItemProperty -Path $RegPath -Name 'Scancode Map' -PropertyType Binary -Value $m -Force | Out-Null
    Write-Host ''
    Write-Host ('  Записано: ' + (Show-Hex $m)) -ForegroundColor Green
    foreach ($r in $rules) {
        if ($r.to -eq 0) { Write-Host ("    0x{0:X2} ({1}) — вимкнено" -f $r.from, (Name-Of $r.from)) }
        else             { Write-Host ("    0x{0:X2} ({1}) тепер друкує те, що 0x{2:X2}" -f $r.from, (Name-Of $r.from), $r.to) }
    }
    Write-Host ''
    Write-Host '  ПЕРЕЗАВАНТАЖТЕ комп''ютер — драйвер читає цей параметр лише при старті.' -ForegroundColor Yellow
}

function Ask-Scancode {
    Write-Host ''
    Write-Host '  Найчастіші винуватці:' -ForegroundColor Cyan
    foreach ($k in $KNOWN.Keys) { Write-Host ("    0x{0:X2}  {1}" -f $k, $KNOWN[$k]) }
    Write-Host ''
    Write-Host '  Не знаєте код? Відкрийте поруч «Скан-код клавіші.html» і натисніть биту клавішу.' -ForegroundColor DarkGray
    $s = Read-Host '  Скан-код (Enter = 0x56)'
    if ([string]::IsNullOrWhiteSpace($s)) { return 0x56 }
    $s = $s.Trim() -replace '^0[xX]', ''
    try { return [Convert]::ToInt32($s, 16) } catch { Write-Host '  Не схоже на шістнадцятковий код.' -ForegroundColor Red; return 0 }
}

# --- меню ---------------------------------------------------------------------
Clear-Host
Write-Host '===========================================================' -ForegroundColor Cyan
Write-Host '  Залипла клавіша — вимкнення через реєстр' -ForegroundColor Cyan
Write-Host '===========================================================' -ForegroundColor Cyan
Show-Current

Write-Host ''
Write-Host '  1  Вимкнути биту клавішу'
Write-Host '  2  Вимкнути биту і перенести її літеру на клавішу «Меню»'
Write-Host '  3  Скасувати все, повернути заводський стан'
Write-Host '  0  Вийти, нічого не чіпаючи'
Write-Host ''
$choice = Read-Host '  Ваш вибір'

switch ($choice) {
    '1' {
        $sc = Ask-Scancode
        if ($sc -gt 0) { Write-Map @( @{ from = $sc; to = 0 } ) }
    }
    '2' {
        $sc = Ask-Scancode
        if ($sc -gt 0) {
            if ($sc -eq 0xE05D) { Write-Host '  Це і є клавіша «Меню» — переносити нікуди.' -ForegroundColor Red }
            else { Write-Map @( @{ from = $sc; to = 0 }, @{ from = 0xE05D; to = $sc } ) }
        }
    }
    '3' {
        try {
            Remove-ItemProperty -Path $RegPath -Name 'Scancode Map' -ErrorAction Stop
            Write-Host ''
            Write-Host '  Повернуто заводський стан. Перезавантажте комп''ютер.' -ForegroundColor Green
        } catch {
            Write-Host ''
            Write-Host '  Перевизначень і не було — нічого скасовувати.' -ForegroundColor Green
        }
    }
    default { Write-Host ''; Write-Host '  Нічого не змінено.' -ForegroundColor DarkGray }
}

Write-Host ''
Read-Host '  Enter — закрити' | Out-Null

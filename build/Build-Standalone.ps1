# =============================================================================
#  Збирає ОДИН самодостатній .cmd із вбудованим графічним скриптом.
#
#  Навіщо: клієнтові зручно отримати один файл, який нічого не встановлює.
#
#  ПАСТКА, на якій перша версія мовчки ламалась: дані складались у змінну
#  через `set "B=!B!..."`. Межа командного рядка cmd.exe — 8191 символ, і при
#  відкладеному розгортанні `!B!` у цю межу рахується ВЕСЬ накопичений вміст,
#  а не довжина рядка у файлі. Щойно змінна переростала межу, cmd переставав
#  дописувати — без помилки й без попередження. З 17000 символів доїжджало 8100,
#  тож програма розпаковувалась наполовину й не запускалась.
#
#  Тепер шматки пишуться у файл, де жодних меж немає. Дужки навколо echo
#  обов'язкові: без них рядок, що закінчується цифрою, cmd читає як
#  перенаправлення потоку (`...1>>файл`), а в base64 цифри всюди.
#
#  Base64 — бо cmd.exe читає власний файл у кодуванні консолі, і кирилиця
#  прямо в ньому перетворюється на кашу.
#  Розпакування в C:\Users\Public: цей шлях завжди латиницею, а тека
#  користувача може зватися кирилицею й зламати передачу шляху.
# =============================================================================
[CmdletBinding()]
param(
    [string] $Source = (Join-Path (Split-Path $PSScriptRoot -Parent) 'src\KeyFix.Gui.ps1'),
    [string] $Output = (Join-Path (Split-Path $PSScriptRoot -Parent) 'dist\KeyFix.cmd')
)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $Source)) { throw "Немає джерела: $Source" }
New-Item -ItemType Directory -Force (Split-Path $Output -Parent) | Out-Null

# Скрипт має лягти у файл як UTF-8 З BOM: PowerShell 5.1 без BOM читає
# кирилицю як ANSI і весь текст інтерфейсу перетворюється на кашу.
$text  = [IO.File]::ReadAllText($Source, (New-Object Text.UTF8Encoding($false)))
$bytes = (New-Object Text.UTF8Encoding($true)).GetPreamble() + [Text.Encoding]::UTF8.GetBytes($text)
$b64   = [Convert]::ToBase64String($bytes)

$L = [System.Collections.Generic.List[string]]::new()
$L.Add('@echo off')
$L.Add('rem =========================================================================')
$L.Add('rem  KeyFix - disable a stuck keyboard key (registry Scancode Map).')
$L.Add('rem  Single file, nothing to install. Asks for administrator rights itself.')
$L.Add('rem  ASCII only on purpose; the Ukrainian UI text is base64 below (UTF-8).')
$L.Add('rem  https://github.com/sgmnl2/keyfix')
$L.Add('rem =========================================================================')
$L.Add('setlocal')
$L.Add('set "B64=%TEMP%\thkeyfix.b64"')
$L.Add('set "TARGET=%PUBLIC%\TechHub_KeyFix.ps1"')

$chunk = 900
$first = $true
for ($i = 0; $i -lt $b64.Length; $i += $chunk) {
    $len = [Math]::Min($chunk, $b64.Length - $i)
    $op  = if ($first) { '>' } else { '>>' }
    $L.Add('(echo ' + $b64.Substring($i, $len) + ')' + $op + '"%B64%"')
    $first = $false
}

$L.Add('powershell -NoProfile -ExecutionPolicy Bypass -Command "[IO.File]::WriteAllBytes($env:TARGET,[Convert]::FromBase64String(-join ([IO.File]::ReadAllLines($env:B64))))"')
$L.Add('if not exist "%TARGET%" (')
$L.Add('  echo.')
$L.Add('  echo Could not unpack the tool. Antivirus may have blocked it.')
$L.Add('  echo.')
$L.Add('  pause')
$L.Add('  goto cleanup')
$L.Add(')')
$L.Add('net session >nul 2>&1')
$L.Add('if "%errorlevel%"=="0" (')
$L.Add('  powershell -NoProfile -ExecutionPolicy Bypass -STA -File "%TARGET%"')
$L.Add(') else (')
$L.Add('  powershell -NoProfile -Command "Start-Process powershell -Verb RunAs -Wait -ArgumentList ''-STA'',''-NoProfile'',''-ExecutionPolicy'',''Bypass'',''-File'',''%TARGET%''"')
$L.Add(')')
$L.Add(':cleanup')
$L.Add('powershell -NoProfile -Command "foreach($p in @($env:TARGET,$env:B64)){ if($p -and (Test-Path -LiteralPath $p)){ [IO.File]::Delete($p) } }"')
$L.Add('exit')

[IO.File]::WriteAllText($Output, ($L -join "`r`n") + "`r`n", (New-Object Text.ASCIIEncoding))

# --- самоперевірка ------------------------------------------------------------
# Міряємо саме те, чого не вистачало першій версії: чи доїжджає навантаження
# цілим. Довжина рядків у файлі нічого не доводить — важливо, що збере cmd.
$t   = [IO.File]::ReadAllText($Output)
$bad = ($t.ToCharArray() | Where-Object { [int]$_ -gt 127 }).Count
$max = ($t -split "`r?`n" | ForEach-Object { $_.Length } | Measure-Object -Maximum).Maximum
$n   = ($t -split "`r?`n" | Where-Object { $_ -like '(echo *' }).Count

Write-Host ("зібрано: {0}  ({1:N1} КБ)" -f (Split-Path $Output -Leaf), ((Get-Item $Output).Length / 1KB))
Write-Host ("  не-ASCII символів: {0} (має бути 0)" -f $bad)
Write-Host ("  найдовший рядок:   {0} (межа cmd.exe 8191)" -f $max)
Write-Host ("  шматків base64:    {0}, загалом {1} символів" -f $n, $b64.Length)

if ($bad -ne 0)   { throw 'У .cmd потрапили не-ASCII символи — кирилиця зіпсується.' }
if ($max -ge 8000) { throw 'Рядок задовгий для cmd.exe.' }
Write-Host '  OK' -ForegroundColor Green

# =============================================================================
#  «Несправна клавіша» — вікно для клієнта. Вимикає залиплу клавішу через
#  Scancode Map у реєстрі: драйвер клавіатури перестає її помічати ще до
#  розкладок і до входу в систему, тож символ не з'явиться ніде й ніколи.
#
#  Вікно, а не консоль, бо це бачить клієнт, а не технік.
#  Запускається з .cmd-обгортки, яка сама просить права адміністратора.
# =============================================================================
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

# Вікно, що читає СИРИЙ скан-код прямо з повідомлення Windows, а не вгадує його
# через розкладку. У lParam повідомлення про натискання: біти 16-23 — апаратний
# скан-код, біт 24 — ознака розширеної клавіші (префікс E0), біт 30 — попередній
# стан, тобто «це вже повтор». Саме біт 30 і викриває залиплу клавішу.
#
# Повідомлення проковтуємо, щоб ніщо не друкувалось у вікні. Escape пропускаємо —
# має лишитись спосіб закрити вікно з клавіатури.
Add-Type -ReferencedAssemblies System.Windows.Forms, System.Drawing -TypeDefinition @'
using System;
using System.Windows.Forms;
public class ScanForm : Form {
    public event Action<int,bool> ScanKey;   // повний скан-код, чи це повтор
    protected override void WndProc(ref Message m) {
        if (m.Msg == 0x100 || m.Msg == 0x104) {          // WM_KEYDOWN / WM_SYSKEYDOWN
            long lp = m.LParam.ToInt64();
            int  sc = (int)((lp >> 16) & 0xFF);
            bool ext = ((lp >> 24) & 1) != 0;
            bool rep = ((lp >> 30) & 1) != 0;
            int  vk = (int)m.WParam.ToInt64();
            if (vk != 0x1B && sc != 0) {                  // 0x1B = Escape
                if (ScanKey != null) ScanKey(ext ? (0xE000 | sc) : sc, rep);
                return;
            }
        }
        if (m.Msg == 0x101 || m.Msg == 0x105) {          // WM_KEYUP / WM_SYSKEYUP
            int vk = (int)m.WParam.ToInt64();
            if (vk != 0x1B) return;
        }
        base.WndProc(ref m);
    }
}
'@

$RegPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Keyboard Layout'

$NAMES = @{
    0x56 = 'додаткова клавіша біля лівого Shift'
    0x2B = 'клавіша \ біля Enter'
    0x28 = "клавіша '"
    0x1A = 'клавіша ['
    0x1B = 'клавіша ]'
    0x27 = 'клавіша ;'
    0x33 = 'клавіша ,'
    0x34 = 'клавіша .'
    0x39 = 'пробіл'
    0x0E = 'Backspace'
    0x1C = 'Enter'
    0x3A = 'Caps Lock'
    0x0F = 'Tab'
    0x01 = 'Escape'
    0xE05D = 'клавіша «Меню»'
    0xE01D = 'правий Ctrl'
    0xE038 = 'правий Alt'
}
# Клавіші, без яких працювати неможливо: вимикати не даємо.
$LOCKED = @(0x1C, 0x0E, 0x39, 0x1D, 0x2A, 0x36, 0x38, 0xE01D, 0xE038)

function Get-Map {
    try { return (Get-ItemProperty -Path $RegPath -Name 'Scancode Map' -ErrorAction Stop).'Scancode Map' } catch { return $null }
}

function Describe-State {
    $v = Get-Map
    if (-not $v) { return 'Зараз нічого не вимкнено — клавіатура в заводському стані.' }
    $n = [BitConverter]::ToUInt32($v, 8) - 1
    $parts = @()
    for ($i = 0; $i -lt $n; $i++) {
        $o = 12 + $i * 4
        $from = [BitConverter]::ToUInt16($v, $o + 2)
        $nm = if ($NAMES.ContainsKey([int]$from)) { $NAMES[[int]$from] } else { 'клавіша' }
        $parts += ('{0} (код 0x{1:X2})' -f $nm, $from)
    }
    return 'Уже вимкнено: ' + ($parts -join '; ')
}

# --- вікно --------------------------------------------------------------------
$f = New-Object ScanForm
$f.Text = 'Несправна клавіша'
$f.Size = New-Object Drawing.Size(580, 475)
$f.StartPosition = 'CenterScreen'
$f.FormBorderStyle = 'FixedDialog'
$f.MaximizeBox = $false
$f.KeyPreview = $true
$f.Font = New-Object Drawing.Font('Segoe UI', 9.75)
$f.BackColor = [Drawing.Color]::White

$lblTop = New-Object Windows.Forms.Label
$lblTop.Text = "Якщо якась клавіша друкує сама собою, її можна вимкнути. Вона перестане реагувати, а решта клавіатури працюватиме як завжди."
$lblTop.SetBounds(20, 14, 525, 46)
$lblTop.ForeColor = [Drawing.Color]::FromArgb(70, 70, 70)
$f.Controls.Add($lblTop)

$grp = New-Object Windows.Forms.GroupBox
$grp.Text = ' Крок 1 — покажіть, яка клавіша несправна '
$grp.SetBounds(20, 68, 525, 118)
$f.Controls.Add($grp)

$lblAsk = New-Object Windows.Forms.Label
$lblAsk.Text = 'Натисніть її просто зараз. Якщо вона друкує сама — зачекайте секунду.'
$lblAsk.SetBounds(15, 26, 495, 20)
$grp.Controls.Add($lblAsk)

$lblKey = New-Object Windows.Forms.Label
$lblKey.Text = 'чекаю натискання…'
$lblKey.SetBounds(15, 50, 495, 30)
$lblKey.Font = New-Object Drawing.Font('Segoe UI', 13, [Drawing.FontStyle]::Bold)
$lblKey.ForeColor = [Drawing.Color]::FromArgb(130, 130, 130)
$grp.Controls.Add($lblKey)

$lblRep = New-Object Windows.Forms.Label
$lblRep.SetBounds(15, 84, 495, 20)
$lblRep.ForeColor = [Drawing.Color]::FromArgb(180, 60, 40)
$grp.Controls.Add($lblRep)

$btnOff = New-Object Windows.Forms.Button
$btnOff.Text = 'Вимкнути цю клавішу'
$btnOff.SetBounds(20, 205, 252, 46)
$btnOff.Enabled = $false
$f.Controls.Add($btnOff)

$btnUndo = New-Object Windows.Forms.Button
$btnUndo.Text = 'Повернути все як було'
$btnUndo.SetBounds(293, 205, 252, 46)
$f.Controls.Add($btnUndo)

$lblState = New-Object Windows.Forms.Label
$lblState.SetBounds(20, 266, 525, 40)
$lblState.ForeColor = [Drawing.Color]::FromArgb(20, 110, 50)
$f.Controls.Add($lblState)

$lblNote = New-Object Windows.Forms.Label
$lblNote.Text = "Зміна діє після перезавантаження комп'ютера. Її завжди можна скасувати кнопкою праворуч."
$lblNote.SetBounds(20, 312, 525, 44)
$lblNote.ForeColor = [Drawing.Color]::FromArgb(110, 110, 110)
$f.Controls.Add($lblNote)

$btnClose = New-Object Windows.Forms.Button
$btnClose.Text = 'Закрити'
$btnClose.SetBounds(445, 368, 100, 34)
$btnClose.Add_Click({ $f.Close() })
$f.Controls.Add($btnClose)

$script:sc = 0
$script:lastVk = -1
$script:streak = 0

$f.add_ScanKey({
    param($code, $isRepeat)
    if ($code -eq 0) { return }

    if ($code -eq $script:lastVk) { $script:streak++ } else { $script:streak = 1 }
    $script:lastVk = $code
    $script:sc = $code

    # Модифікатори, які утримуються просто зараз. Якщо символ народжується
    # сполученням, людина має побачити, що саме прилітає.
    $m = [Windows.Forms.Control]::ModifierKeys
    $mods = @()
    if ($m -band [Windows.Forms.Keys]::Control) { $mods += 'Ctrl' }
    if ($m -band [Windows.Forms.Keys]::Alt)     { $mods += 'Alt' }
    if ($m -band [Windows.Forms.Keys]::Shift)   { $mods += 'Shift' }

    $nm = if ($NAMES.ContainsKey($code)) { $NAMES[$code] } else { 'клавіша' }
    $prefix = if ($mods.Count) { ($mods -join ' + ') + ' + ' } else { '' }
    $lblKey.Text = ('{0}{1}   (код 0x{2:X2})' -f $prefix, $nm, $code)
    $lblKey.ForeColor = [Drawing.Color]::FromArgb(20, 20, 20)

    if ($LOCKED -contains $code) {
        $lblRep.Text = 'Без цієї клавіші працювати неможливо — вимкнути не дам.'
        $lblRep.ForeColor = [Drawing.Color]::FromArgb(180, 60, 40)
        $btnOff.Enabled = $false
    } elseif ($isRepeat -or $script:streak -ge 3) {
        # Біт 30 у повідомленні каже, що клавіша вже була натиснута, тобто
        # Windows шле автоповтор. Для залиплої клавіші це головний доказ.
        $lblRep.Text = 'Windows отримує повтори — схоже, клавіша залипла.'
        $lblRep.ForeColor = [Drawing.Color]::FromArgb(180, 60, 40)
        $btnOff.Enabled = $true
    } elseif ($mods.Count) {
        # Вимкнути можна лише фізичну клавішу, а не сполучення: драйвер бачить
        # окремі натискання, а Ctrl/Alt/Shift стають «модифікаторами» вже пізніше.
        $lblRep.Text = 'Утримується ' + ($mods -join ' + ') + '. Вимкнути можна лише саму клавішу, не сполучення.'
        $lblRep.ForeColor = [Drawing.Color]::FromArgb(180, 110, 20)
        $btnOff.Enabled = $true
    } else {
        $lblRep.Text = ''
        $btnOff.Enabled = $true
    }
})

# Сторож залиплого модифікатора. Якщо Ctrl, Alt чи Shift значаться натиснутими,
# коли людина нічого не тримає, — винен саме модифікатор, і тоді вимикати
# якусь літеру марно. Це єдиний спосіб побачити «сполучення, що натискається саме».
$watch = New-Object Windows.Forms.Timer
$watch.Interval = 700
$script:stuckTicks = 0
$watch.Add_Tick({
    $m = [Windows.Forms.Control]::ModifierKeys
    if ($m -ne [Windows.Forms.Keys]::None) { $script:stuckTicks++ } else { $script:stuckTicks = 0 }
    if ($script:stuckTicks -ge 4) {
        $held = @()
        if ($m -band [Windows.Forms.Keys]::Control) { $held += 'Ctrl' }
        if ($m -band [Windows.Forms.Keys]::Alt)     { $held += 'Alt' }
        if ($m -band [Windows.Forms.Keys]::Shift)   { $held += 'Shift' }
        $lblRep.Text = 'Залипла службова клавіша: ' + ($held -join ' + ') + '. Саме вона винна, а не літера.'
        $lblRep.ForeColor = [Drawing.Color]::FromArgb(180, 60, 40)
    }
})
$watch.Start()

$btnOff.Add_Click({
    if ($script:sc -le 0) { return }
    $nm = if ($NAMES.ContainsKey($script:sc)) { $NAMES[$script:sc] } else { 'обрану клавішу' }
    $ans = [Windows.Forms.MessageBox]::Show(
        ("Вимкнути {0}?`n`nВона перестане працювати повністю. Скасувати можна цією ж програмою." -f $nm),
        'Підтвердження', 'YesNo', 'Question')
    if ($ans -ne 'Yes') { return }
    try {
        $m = [System.Collections.Generic.List[byte]]::new()
        $m.AddRange([byte[]]@(0,0,0,0, 0,0,0,0))
        $m.AddRange([BitConverter]::GetBytes([uint32]2))
        $m.AddRange([byte[]]@(0, 0, ($script:sc -band 0xFF), (($script:sc -shr 8) -band 0xFF)))
        $m.AddRange([byte[]]@(0,0,0,0))
        New-ItemProperty -Path $RegPath -Name 'Scancode Map' -PropertyType Binary -Value $m.ToArray() -Force | Out-Null
        $lblState.Text = Describe-State
        [Windows.Forms.MessageBox]::Show(
            "Готово.`n`nПерезавантажте комп'ютер — після цього клавіша мовчатиме скрізь, зокрема на екрані входу.",
            'Збережено', 'OK', 'Information') | Out-Null
    } catch {
        [Windows.Forms.MessageBox]::Show("Не вдалося записати: $($_.Exception.Message)", 'Помилка', 'OK', 'Error') | Out-Null
    }
})

$btnUndo.Add_Click({
    try {
        Remove-ItemProperty -Path $RegPath -Name 'Scancode Map' -ErrorAction Stop
        $lblState.Text = Describe-State
        [Windows.Forms.MessageBox]::Show("Повернуто заводський стан.`n`nПерезавантажте комп'ютер.", 'Готово', 'OK', 'Information') | Out-Null
    } catch {
        [Windows.Forms.MessageBox]::Show('Нічого не було вимкнено — скасовувати нічого.', 'Готово', 'OK', 'Information') | Out-Null
    }
})

$lblState.Text = Describe-State
$f.Add_Shown({ $f.Activate() })
[void]$f.ShowDialog()

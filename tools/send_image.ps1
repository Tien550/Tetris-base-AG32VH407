# Gui anh RGB565 (.raw, 768000 byte) len man hinh HMI qua UART.
#   .\tools\send_image.ps1 -File anh.raw -Port COM17 [-Baud 115200]
# Giao thuc: gui "IMG!" -> cho board tra 'K' -> gui 768000 byte. Dong serial monitor truoc khi chay.
param(
    [Parameter(Mandatory = $true)][string]$File,
    [string]$Port = "COM17",
    [int]$Baud = 115200,
    [switch]$Save    # luu anh vao flash SPI ngoai lam anh khoi dong (board se tu hien khi bat nguon)
)
$data = [System.IO.File]::ReadAllBytes($File)
if ($data.Length -ne 768000) { Write-Error "File phai dung 768000 byte (hien $($data.Length))"; exit 1 }

$p = New-Object System.IO.Ports.SerialPort $Port, $Baud, 'None', 8, 'One'
$p.ReadTimeout = 300; $p.WriteTimeout = 20000
try { $p.Open() } catch { Write-Error "Khong mo duoc $Port (dong serial monitor?): $_"; exit 1 }
try {
    $p.DiscardInBuffer()
    $magic = "IMG!"; if ($Save) { $magic = "IMF!" }
    $hdr = [System.Text.Encoding]::ASCII.GetBytes($magic)
    $ok = $false
    for ($try = 0; $try -lt 20 -and -not $ok; $try++) {     # board co the dang ve, thu lai toi da ~20 s
        $p.Write($hdr, 0, 4)
        $t0 = Get-Date
        while (((Get-Date) - $t0).TotalMilliseconds -lt 1000) {
            try { if ($p.ReadByte() -eq 75) { $ok = $true; break } } catch { }   # 75 = 'K'
        }
    }
    if (-not $ok) { Write-Error "Board khong tra loi. Da nap firmware moi chua?"; exit 1 }

    $chunk = 512; $sent = 0; $last = -1
    while ($sent -lt $data.Length) {
        $n = [Math]::Min($chunk, $data.Length - $sent)
        $p.Write($data, $sent, $n); $sent += $n
        $pct = [int](100 * $sent / $data.Length)
        if ($pct -ne $last -and $pct % 10 -eq 0) { Write-Host "$pct%"; $last = $pct }
    }
    Write-Host "Da gui xong."
    if ($Save) {
        Write-Host "Dang luu vao flash (xoa + ghi + kiem tra, khoang 10-20 giay)..."
        $p.ReadTimeout = 60000
        try {
            $r = $p.ReadByte()
            if ($r -eq 83) { Write-Host "DA LUU: bat nguon lai se tu hien anh." }
            else { Write-Error "Luu that bai (xem UART)."; exit 1 }
        } catch { Write-Error "Khong nhan duoc xac nhan luu."; exit 1 }
    }
} finally { if ($p.IsOpen) { $p.Close() } }

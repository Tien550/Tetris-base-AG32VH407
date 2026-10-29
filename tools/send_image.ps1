# Stream an RGB565 raw image (.raw, 768,000 bytes) to the AGM HMI display over UART.
# Usage:
#   .\tools\send_image.ps1 -File image.raw -Port COM17 [-Baud 115200] [-Save]
# Protocol: Sends "IMG!" (or "IMF!" with -Save) -> waits for 'K' -> streams 768,000 bytes.
# Note: Ensure serial monitor is closed before running this script.

param(
    [Parameter(Mandatory = $true)][string]$File,
    [string]$Port = "COM17",
    [int]$Baud = 115200,
    [switch]$Save    # Save image to external SPI flash as persistent splash screen
)

if (-not (Test-Path $File)) {
    Write-Error "File not found: $File"
    exit 1
}

$data = [System.IO.File]::ReadAllBytes($File)
if ($data.Length -ne 768000) {
    Write-Error "File size must be exactly 768,000 bytes (current size: $($data.Length))"
    exit 1
}

$p = New-Object System.IO.Ports.SerialPort $Port, $Baud, 'None', 8, 'One'
$p.ReadTimeout = 300
$p.WriteTimeout = 20000

try {
    $p.Open()
} catch {
    Write-Error "Failed to open $Port. Please ensure the serial monitor is closed: $_"
    exit 1
}

try {
    $p.DiscardInBuffer()
    $magic = if ($Save) { "IMF!" } else { "IMG!" }
    $hdr = [System.Text.Encoding]::ASCII.GetBytes($magic)
    $ok = $false

    # Retry handshake for up to 20 attempts
    for ($try = 0; $try -lt 20 -and -not $ok; $try++) {
        $p.Write($hdr, 0, 4)
        $t0 = Get-Date
        while (((Get-Date) - $t0).TotalMilliseconds -lt 1000) {
            try {
                if ($p.ReadByte() -eq 75) { # ASCII 75 = 'K'
                    $ok = $true
                    break
                }
            } catch { }
        }
    }

    if (-not $ok) {
        Write-Error "Board did not respond to handshake. Is the firmware running?"
        exit 1
    }

    $chunk = 512
    $sent = 0
    $last = -1
    while ($sent -lt $data.Length) {
        $n = [Math]::Min($chunk, $data.Length - $sent)
        $p.Write($data, $sent, $n)
        $sent += $n
        $pct = [int](100 * $sent / $data.Length)
        if ($pct -ne $last -and $pct % 10 -eq 0) {
            Write-Host "Progress: $pct%"
            $last = $pct
        }
    }
    Write-Host "Transmission completed successfully."

    if ($Save) {
        Write-Host "Saving to external SPI flash (erase + program + verify, ~10-20s)..."
        $p.ReadTimeout = 60000
        try {
            $r = $p.ReadByte()
            if ($r -eq 83) { # ASCII 83 = 'S' (Success)
                Write-Host "SAVED: Splash screen image will now automatically display on power-up."
            } else {
                Write-Error "Flash save failed (check UART log output)."
                exit 1
            }
        } catch {
            Write-Error "Timed out waiting for save confirmation from board."
            exit 1
        }
    }
} finally {
    if ($p.IsOpen) {
        $p.Close()
    }
}

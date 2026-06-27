# hyprctl.ps1
param (
    [string]$Command = ""
)

if (-not $Command) {
    Write-Host "Usage: .\hyprctl.ps1 'dispatch workspace 2'" -ForegroundColor Yellow
    exit
}

$pipe = New-Object System.IO.Ports.SerialPort # Alternative: raw File stream
$pipe = [System.IO.Path]::GetFullPath("\\.\pipe\hyprwin")

try {
    $fs = [System.IO.File]::OpenWrite($pipe)
    $writer = New-Object System.IO.StreamWriter($fs)
    $writer.Write($Command)
    $writer.Flush()
    $writer.Close()
    $fs.Close()
    
    # Read response
    $fsRead = [System.IO.File]::OpenRead($pipe)
    $reader = New-Object System.IO.StreamReader($fsRead)
    $res = $reader.ReadToEnd()
    $reader.Close()
    $fsRead.Close()
    
    Write-Host $res -ForegroundColor Green
} catch {
    Write-Error "Failed to connect to HyprWin IPC: $_"
}
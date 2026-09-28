param (
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Command
)

$pipe = New-Object System.IO.Pipes.NamedPipeClientStream(".", "hyprwin", [System.IO.Pipes.PipeDirection]::InOut)

try {
    $pipe.Connect(1000)
    $writer = New-Object System.IO.StreamWriter($pipe)
    $reader = New-Object System.IO.StreamReader($pipe)

    $writer.Write($Command)
    $writer.Flush()

    $response = $reader.ReadToEnd()
    Write-Host $response
}
catch {
    Write-Error "HyprWin IPC unreachable: $_"
}
finally {
    $pipe.Dispose()
}
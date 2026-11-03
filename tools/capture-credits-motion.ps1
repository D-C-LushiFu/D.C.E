param(
    [Parameter(Mandatory = $true)][int]$TargetProcessId,
    [Parameter(Mandatory = $true)][string]$RunDirectory,
    [int]$Seconds = 9,
    [int]$FPS = 12,
    [int]$ClickX = -1,
    [int]$ClickY = -1,
    [switch]$Replay
)
$ErrorActionPreference = 'Stop'
# Reuse the existing window probe's Win32 declarations and scope capture to this preview.
. "$PSScriptRoot\probe-novaflare-window.ps1" -TargetProcessId $TargetProcessId -RunDirectory $RunDirectory -Name 'seed' -Key None | Out-Null
[DCEWindowProbeNative]::SetForegroundWindow($window) | Out-Null
Start-Sleep -Milliseconds 150
if ([DCEWindowProbeNative]::GetForegroundWindow() -ne $window) { throw 'Preview must be foreground before capture.' }
if ($ClickX -ge 0 -and $ClickY -ge 0) {
    [DCEWindowProbeNative]::SetCursorPos($rect.Left + $ClickX, $rect.Top + $ClickY) | Out-Null
    [DCEWindowProbeNative]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 40
    [DCEWindowProbeNative]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
}
if ($Replay) {
    [DCEWindowProbeNative]::keybd_event(0x52, 0x13, 0, [UIntPtr]::Zero)
    Start-Sleep -Milliseconds 35
    [DCEWindowProbeNative]::keybd_event(0x52, 0x13, 2, [UIntPtr]::Zero)
}
$timer = [Diagnostics.Stopwatch]::StartNew()
$frameTimes = [Collections.Generic.List[object]]::new()
for ($frame = 0; $frame -lt $Seconds * $FPS; $frame++) {
    $delay = $frame * 1000 / $FPS - $timer.ElapsedMilliseconds
    if ($delay -gt 0) { Start-Sleep -Milliseconds ([int]$delay) }
    # Never capture another application if the user changes focus during verification.
    if ([DCEWindowProbeNative]::GetForegroundWindow() -ne $window) { throw 'Focus changed; capture stopped.' }
    $bitmap = [Drawing.Bitmap]::new($width, $height)
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    try {
        $graphics.CopyFromScreen($rect.Left, $rect.Top, 0, 0, [Drawing.Size]::new($width, $height), [Drawing.CopyPixelOperation]::SourceCopy)
        $framePath = Join-Path $RunDirectory ('frame-{0:D3}.png' -f $frame)
        $bitmap.Save($framePath, [Drawing.Imaging.ImageFormat]::Png)
        $frameTimes.Add([pscustomobject]@{Frame = $frame; Milliseconds = $timer.ElapsedMilliseconds})
    }
    finally { $graphics.Dispose(); $bitmap.Dispose() }
}
$frameTimes | ConvertTo-Json | Set-Content (Join-Path $RunDirectory 'timing.json')
[pscustomobject]@{Frames = $frameTimes.Count; Width = $width; Height = $height; Directory = $RunDirectory}

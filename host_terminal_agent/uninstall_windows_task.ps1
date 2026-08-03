[CmdletBinding()]
param(
    [string]$TaskName = "AI-Deep Monitor - Terminal hote protege"
)

$ErrorActionPreference = "Stop"
$existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existing) {
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "Tache planifiee supprimee : $TaskName"
}

$launcherPath = Join-Path ([Environment]::GetFolderPath("Startup")) "AI-Deep-Monitor-Terminal.vbs"
if (Test-Path -LiteralPath $launcherPath) {
    Remove-Item -LiteralPath $launcherPath -Force
    Write-Host "Demarrage utilisateur supprime : $launcherPath"
}

if (-not $existing -and -not (Test-Path -LiteralPath $launcherPath)) {
    Write-Host "Aucun demarrage automatique restant."
}

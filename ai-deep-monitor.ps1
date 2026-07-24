param(
  [string]$InstallDir = "C:\ai-deep-monitor",
  [ValidateSet("", "install", "update", "status", "logs", "backup", "restore", "stop", "start", "uninstall", "purge", "help")]
  [string]$Command = ""
)

$ErrorActionPreference = "Stop"
$scriptDir = $PSScriptRoot
$internalDir = Join-Path $scriptDir "scripts\windows"
if (-not (Test-Path -LiteralPath $internalDir -PathType Container)) {
  $internalDir = $scriptDir
}

function Invoke-KitScript {
  param(
    [string]$Name,
    [hashtable]$Arguments = @{}
  )
  $path = Join-Path $internalDir $Name
  if (-not (Test-Path -LiteralPath $path)) {
    throw "$Name introuvable dans $internalDir"
  }
  & $path @Arguments
}

function Get-ComposeContext {
  $compose = Join-Path $InstallDir "docker-compose.release.yml"
  $envFile = Join-Path $InstallDir ".env"
  if (-not (Test-Path -LiteralPath $compose) -or -not (Test-Path -LiteralPath $envFile)) {
    throw "Installation introuvable dans $InstallDir. Choisis d'abord Installer / reparer."
  }
  return @{ Compose = $compose; Env = $envFile }
}

function Invoke-Compose {
  param([string[]]$Arguments)
  $context = Get-ComposeContext
  & docker compose -f $context.Compose --env-file $context.Env @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "La commande Docker Compose a echoue."
  }
}

function Show-Help {
  Write-Host @"
AI Deep Monitor - outil client Windows

Utilisation interactive:
  .\ai-deep-monitor.ps1

Commandes directes:
  .\ai-deep-monitor.ps1 -Command install
  .\ai-deep-monitor.ps1 -Command update
  .\ai-deep-monitor.ps1 -Command status
  .\ai-deep-monitor.ps1 -Command logs
  .\ai-deep-monitor.ps1 -Command backup
  .\ai-deep-monitor.ps1 -Command restore
  .\ai-deep-monitor.ps1 -Command stop
  .\ai-deep-monitor.ps1 -Command start
  .\ai-deep-monitor.ps1 -Command uninstall
  .\ai-deep-monitor.ps1 -Command purge

Chemin personnalise:
  .\ai-deep-monitor.ps1 -InstallDir D:\AI-Deep-Monitor
"@
}

function Invoke-SelectedCommand {
  param([string]$Selected)
  switch ($Selected) {
    "install" {
      Invoke-KitScript "install-client.ps1" @{ InstallDir = $InstallDir }
    }
    "update" {
      Invoke-KitScript "update-client.ps1" @{ InstallDir = $InstallDir }
    }
    "status" {
      Invoke-Compose @("ps", "-a")
    }
    "logs" {
      Invoke-Compose @("logs", "--tail=200")
    }
    "backup" {
      Invoke-KitScript "backup-client.ps1" @{ InstallDir = $InstallDir }
    }
    "restore" {
      $backupFile = Read-Host "Chemin complet de la sauvegarde .zip"
      if (-not $backupFile) { throw "Aucune sauvegarde selectionnee." }
      Invoke-KitScript "restore-client.ps1" @{
        InstallDir = $InstallDir
        BackupFile = $backupFile
      }
    }
    "stop" {
      Invoke-Compose @("stop")
    }
    "start" {
      Invoke-Compose @("up", "-d")
    }
    "uninstall" {
      Invoke-KitScript "uninstall-client.ps1" @{
        InstallDir = $InstallDir
        Mode = "Partial"
      }
    }
    "purge" {
      Write-Warning "Cette operation supprime l'application, MySQL, les volumes et les images Docker."
      Write-Host "Une sauvegarde externe sera creee avant la suppression."
      $confirmation = Read-Host "Saisis SUPPRIMER pour confirmer"
      if ($confirmation -cne "SUPPRIMER") {
        Write-Host "Suppression complete annulee."
        return
      }
      Invoke-KitScript "uninstall-client.ps1" @{
        InstallDir = $InstallDir
        Mode = "Full"
        RemoveImages = $true
        Yes = $true
      }
    }
    "help" {
      Show-Help
    }
    default {
      throw "Commande inconnue: $Selected"
    }
  }
}

if ($Command) {
  Invoke-SelectedCommand $Command
  exit 0
}

while ($true) {
  Clear-Host
  Write-Host "AI Deep Monitor" -ForegroundColor Cyan
  Write-Host "Installation : $InstallDir"
  Write-Host ""
  Write-Host "  1. Installer ou reparer"
  Write-Host "  2. Verifier et installer une mise a jour"
  Write-Host "  3. Afficher l'etat des services"
  Write-Host "  4. Afficher les journaux"
  Write-Host "  5. Creer une sauvegarde"
  Write-Host "  6. Restaurer une sauvegarde"
  Write-Host "  7. Arreter l'application"
  Write-Host "  8. Demarrer l'application"
  Write-Host "  9. Desinstaller en conservant les donnees"
  Write-Host " 10. TOUT SUPPRIMER"
  Write-Host "  0. Quitter"
  Write-Host ""
  $choice = Read-Host "Votre choix"
  $selected = switch ($choice) {
    "1" { "install" }
    "2" { "update" }
    "3" { "status" }
    "4" { "logs" }
    "5" { "backup" }
    "6" { "restore" }
    "7" { "stop" }
    "8" { "start" }
    "9" { "uninstall" }
    "10" { "purge" }
    "0" { return }
    default { "" }
  }
  if (-not $selected) {
    Write-Warning "Choix invalide."
    Start-Sleep -Seconds 1
    continue
  }
  try {
    Invoke-SelectedCommand $selected
  } catch {
    Write-Error $_
  }
  Write-Host ""
  Read-Host "Appuie sur Entree pour revenir au menu" | Out-Null
}

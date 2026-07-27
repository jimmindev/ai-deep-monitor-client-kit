param(
  [string]$InstallDir = "C:\ai-deep-monitor",
  [ValidateSet("", "install", "update", "status", "logs", "backup", "backups", "restore", "stop", "start", "uninstall", "purge", "help")]
  [string]$Command = "",
  [ValidateSet("Menu", "List", "Prune", "DeleteAll")]
  [string]$BackupAction = "Menu",
  [ValidateRange(0, 10000)]
  [int]$KeepBackups = 5,
  [switch]$Yes
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
  .\ai-deep-monitor.ps1 -Command backups
  .\ai-deep-monitor.ps1 -Command restore
  .\ai-deep-monitor.ps1 -Command stop
  .\ai-deep-monitor.ps1 -Command start
  .\ai-deep-monitor.ps1 -Command uninstall
  .\ai-deep-monitor.ps1 -Command purge

Chemin personnalise:
  .\ai-deep-monitor.ps1 -InstallDir D:\AI-Deep-Monitor
"@
}

function Invoke-BackupManagement {
  param(
    [string]$Action = "Menu",
    [int]$Keep = 5
  )

  if ($Action -ne "Menu") {
    Invoke-KitScript "backup-maintenance.ps1" @{
      InstallDir = $InstallDir
      Action = $Action
      Keep = $Keep
      Yes = $Yes
    }
    return
  }

  while ($true) {
    Write-Host ""
    Write-Host "Gestion des sauvegardes" -ForegroundColor Cyan
    Write-Host "  1. Lister les sauvegardes"
    Write-Host "  2. Conserver uniquement les plus recentes"
    Write-Host "  3. Supprimer toutes les sauvegardes"
    Write-Host "  0. Retour"
    $choice = Read-Host "Votre choix"
    switch ($choice) {
      "1" {
        Invoke-KitScript "backup-maintenance.ps1" @{
          InstallDir = $InstallDir
          Action = "List"
        }
      }
      "2" {
        $keepValue = Read-Host "Nombre de sauvegardes recentes a conserver [5]"
        if (-not $keepValue) { $keepValue = 5 }
        Invoke-KitScript "backup-maintenance.ps1" @{
          InstallDir = $InstallDir
          Action = "Prune"
          Keep = [int]$keepValue
        }
      }
      "3" {
        Invoke-KitScript "backup-maintenance.ps1" @{
          InstallDir = $InstallDir
          Action = "DeleteAll"
        }
      }
      "0" { return }
      default { Write-Warning "Choix invalide." }
    }
  }
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
    "backups" {
      Invoke-BackupManagement -Action $BackupAction -Keep $KeepBackups
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

$menuItems = @(
  @{ Label = "Installer ou reparer"; Command = "install" },
  @{ Label = "Verifier et installer une mise a jour"; Command = "update" },
  @{ Label = "Afficher l'etat des services"; Command = "status" },
  @{ Label = "Demarrer l'application"; Command = "start" },
  @{ Label = "Arreter sans supprimer les donnees"; Command = "stop" },
  @{ Label = "Creer une sauvegarde"; Command = "backup" },
  @{ Label = "Gerer ou supprimer les sauvegardes"; Command = "backups" },
  @{ Label = "Restaurer une sauvegarde"; Command = "restore" },
  @{ Label = "Afficher les journaux techniques"; Command = "logs" },
  @{ Label = "Desinstaller en conservant les donnees"; Command = "uninstall" },
  @{ Label = "TOUT SUPPRIMER"; Command = "purge" },
  @{ Label = "Quitter"; Command = "quit" }
)

function Read-InteractiveMenu {
  param([array]$Items)

  $selected = 0
  while ($true) {
    Clear-Host
    Write-Host "AI Deep Monitor" -ForegroundColor Cyan
    Write-Host "Installation : $InstallDir"
    Write-Host ""
    Write-Host "Utilisez les fleches puis Entree." -ForegroundColor DarkGray
    Write-Host ""

    for ($index = 0; $index -lt $Items.Count; $index++) {
      if ($index -eq $selected) {
        Write-Host ("  > {0}" -f $Items[$index].Label) `
          -ForegroundColor White -BackgroundColor DarkBlue
      } else {
        Write-Host ("    {0}" -f $Items[$index].Label)
      }
    }

    try {
      $key = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    } catch {
      return $null
    }

    switch ($key.VirtualKeyCode) {
      38 { $selected = ($selected - 1 + $Items.Count) % $Items.Count }
      40 { $selected = ($selected + 1) % $Items.Count }
      13 { return $Items[$selected].Command }
    }
    if ($key.Character -eq "q" -or $key.Character -eq "Q") {
      return "quit"
    }
  }
}

while ($true) {
  $selected = Read-InteractiveMenu -Items $menuItems
  if ($null -eq $selected) {
    Write-Host ""
    for ($index = 0; $index -lt ($menuItems.Count - 1); $index++) {
      Write-Host (" {0,2}. {1}" -f ($index + 1), $menuItems[$index].Label)
    }
    Write-Host "  0. Quitter"
    $choice = Read-Host "Votre choix"
    $parsedChoice = 0
    if ($choice -eq "0") {
      $selected = "quit"
    } elseif ([int]::TryParse($choice, [ref]$parsedChoice) -and
        $parsedChoice -ge 1 -and $parsedChoice -lt $menuItems.Count) {
      $selected = $menuItems[$parsedChoice - 1].Command
    } else {
      $selected = ""
    }
  }

  if ($selected -eq "quit") {
    return
  }
  if (-not $selected) {
    Write-Warning "Choix invalide."
    Start-Sleep -Seconds 1
    continue
  }
  try {
    Invoke-SelectedCommand $selected
  } catch {
    Write-Host ""
    Write-Host ("[AI Deep Monitor] ERREUR: {0}" -f $_.Exception.Message) `
      -ForegroundColor Red
  }
  Write-Host ""
  Read-Host "Appuyez sur Entree pour revenir au menu" | Out-Null
}

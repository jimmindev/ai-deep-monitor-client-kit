# AI Deep Monitor - Guide client

Ce kit installe AI Deep Monitor sans exposer son code source. Il utilise Docker
et le registre prive GitHub Container Registry.

## Installation rapide Linux

```bash
chmod +x ./*.sh
./install-client.sh
```

Docker est installe automatiquement s'il est absent sur Ubuntu, Debian, Linux
Mint, Fedora, RHEL, Rocky Linux, AlmaLinux et CentOS.

## Installation rapide Windows

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install-client.ps1 -AppVersion v0.1.4
```

Docker Desktop est installe automatiquement avec `winget` s'il est absent.

Pendant l'installation, renseignez votre utilisateur GitHub et un token
autorise a lire les packages prives. Les ports sont choisis automatiquement.

## Commandes Linux

```bash
~/ai-deep-monitor/check-update.sh
~/ai-deep-monitor/update-client.sh
~/ai-deep-monitor/backup-client.sh
~/ai-deep-monitor/restore-client.sh --backup-file CHEMIN.tar.gz
~/ai-deep-monitor/uninstall-client.sh --mode partial
~/ai-deep-monitor/uninstall-client.sh --mode full
```

## Commandes Windows

```powershell
C:\ai-deep-monitor\check-update.ps1
C:\ai-deep-monitor\update-client.ps1
C:\ai-deep-monitor\backup-client.ps1
C:\ai-deep-monitor\restore-client.ps1 -BackupFile "CHEMIN.zip"
C:\ai-deep-monitor\uninstall-client.ps1 -Mode Partial
C:\ai-deep-monitor\uninstall-client.ps1 -Mode Full
```

La desinstallation partielle conserve les donnees. La desinstallation complete
cree d'abord une sauvegarde, puis supprime les volumes et l'installation.

Consultez `README.md` pour les options, la restauration et le diagnostic.

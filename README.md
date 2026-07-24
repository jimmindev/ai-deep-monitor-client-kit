# AI Deep Monitor - Client Kit v0.1.5

Kit prive d'installation, de mise a jour et de maintenance d'AI Deep Monitor.
Il ne contient aucun code source React ou Python. L'application est livree sous
forme d'images Docker privees publiees sur GHCR.

La version du kit est `v0.1.5`. La version applicative stable installee par
defaut reste `v0.1.4`.

## Systemes pris en charge

- Windows 10/11 et Windows Server avec PowerShell 5.1 ou plus recent
- Ubuntu, Debian et Linux Mint
- Fedora, RHEL, Rocky Linux, AlmaLinux et CentOS
- Architecture `amd64` ou toute architecture pour laquelle les images
  applicatives sont publiees

## Prerequis

- Acces Internet pendant l'installation
- Token GitHub autorise a lire les packages prives `ghcr.io`
- Droits administrateur Windows, ou `root`/`sudo` sous Linux
- Espace disque suffisant pour MySQL, les images et le modele Ollama

Docker est verifie automatiquement. S'il est absent:

- Windows: Docker Desktop est installe avec `winget`
- Linux: Docker Engine et Compose v2 sont installes depuis le depot officiel
  Docker de la distribution

## Installation Linux

Extraire l'archive, ouvrir un terminal dans le dossier, puis:

```bash
chmod +x ./*.sh
./install-client.sh
```

Le dossier par defaut est `~/ai-deep-monitor`. Les ports `80` et `8000` sont
utilises lorsqu'ils sont libres; sinon le script choisit automatiquement les
prochains ports disponibles.

Installation personnalisee:

```bash
./install-client.sh \
  --install-dir /opt/ai-deep-monitor \
  --frontend-port 8080 \
  --api-port 8001
```

L'utilisation de `/opt` demande que le dossier soit accessible en ecriture.
Le dossier utilisateur par defaut reste le choix le plus simple.

## Installation Windows

Ouvrir PowerShell dans le dossier du kit:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install-client.ps1 -AppVersion v0.1.4
```

Le dossier par defaut est `C:\ai-deep-monitor`.

## Acces

Avec les ports par defaut:

```text
Application: http://localhost
API health : http://localhost:8000/health
```

Les ports retenus sont enregistres dans le fichier `.env` de l'installation.

## Reprise d'une installation

L'installateur conserve un `.env` existant et reutilise les volumes Docker.
S'il detecte des volumes de donnees sans leur ancien `.env`, il s'arrete pour
eviter de rendre la base MySQL inaccessible avec de nouveaux secrets.

Ne supprimez jamais `.env` sans sauvegarde.

## Verification et mise a jour

Linux:

```bash
~/ai-deep-monitor/check-update.sh
~/ai-deep-monitor/update-client.sh
```

Windows:

```powershell
C:\ai-deep-monitor\check-update.ps1
C:\ai-deep-monitor\update-client.ps1
```

La verification est automatique, mais l'installation de la mise a jour reste
manuelle. Le script de mise a jour cree une sauvegarde avant tout changement.

## Sauvegarde

Linux:

```bash
~/ai-deep-monitor/backup-client.sh
```

Windows:

```powershell
C:\ai-deep-monitor\backup-client.ps1
```

La sauvegarde contient MySQL, les donnees API, les MIB importees et les
sauvegardes applicatives. Le modele Ollama n'est pas inclus et sera
retelcharge si necessaire.

## Restauration

Linux:

```bash
~/ai-deep-monitor/restore-client.sh \
  --backup-file ~/ai-deep-monitor-backups/ai-deep-monitor-v0.1.4-DATE.tar.gz
```

Windows:

```powershell
C:\ai-deep-monitor\restore-client.ps1 -BackupFile "D:\Backups\ai-deep-monitor-v0.1.4-DATE.zip"
```

Linux accepte les sauvegardes `.tar.gz` du kit Linux et les archives `.zip`
produites sous Windows.

## Desinstallation

Partielle, en conservant les volumes et les fichiers:

```bash
~/ai-deep-monitor/uninstall-client.sh --mode partial
```

```powershell
C:\ai-deep-monitor\uninstall-client.ps1 -Mode Partial
```

Complete, avec sauvegarde automatique avant suppression:

```bash
~/ai-deep-monitor/uninstall-client.sh --mode full
```

```powershell
C:\ai-deep-monitor\uninstall-client.ps1 -Mode Full
```

## Diagnostic

Linux:

```bash
cd ~/ai-deep-monitor
docker compose --env-file .env -f docker-compose.release.yml ps
docker compose --env-file .env -f docker-compose.release.yml logs --tail=200
```

Windows:

```powershell
cd C:\ai-deep-monitor
docker compose --env-file .env -f docker-compose.release.yml ps
docker compose --env-file .env -f docker-compose.release.yml logs --tail=200
```

## Securite

- Les sources applicatives ne sont pas livrees au client.
- Les images API et frontend restent dans un registre prive.
- Les secrets sont generes localement et enregistres dans `.env`.
- Sous Linux, `.env` et les sauvegardes sont proteges avec le mode `600`.
- Le token GitHub sert uniquement a lire les images et les versions privees.
- La restauration refuse les archives contenant des chemins dangereux.

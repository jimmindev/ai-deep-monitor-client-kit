# AI Deep Monitor - Guide client

Ce kit installe AI Deep Monitor sans exposer son code source. Il utilise Docker
et le registre prive GitHub Container Registry.

## Telecharger le kit

La derniere version est disponible publiquement ici:

[Telecharger AI Deep Monitor Client Kit](https://github.com/jimmindev/ai-deep-monitor-client-kit/releases/latest)

Liens directs stables, toujours diriges vers la derniere version:

- [Linux `.tar.gz`](https://github.com/jimmindev/ai-deep-monitor-client-kit/releases/latest/download/ai-deep-monitor-client-kit.tar.gz)
- [Windows `.zip`](https://github.com/jimmindev/ai-deep-monitor-client-kit/releases/latest/download/ai-deep-monitor-client-kit.zip)

L'archive s'extrait toujours dans `ai-deep-monitor-client-kit`, quelle que
soit la version du kit. Vous pouvez conserver ce meme chemin pour les
installations et les prochaines mises a jour.

Le depot peut egalement etre clone sans compte GitHub:

```bash
git clone https://github.com/jimmindev/ai-deep-monitor-client-kit.git
cd ai-deep-monitor-client-kit
```

Le kit est public, mais les images Docker applicatives restent privees. Un
token GitHub autorise a lire les packages sera demande pendant l'installation.

## Installation rapide Linux

Telecharger et extraire l'archive Linux:

```bash
mkdir -p ~/aidp
cd ~/aidp
curl -fL \
  -o ai-deep-monitor-client-kit.tar.gz \
  https://github.com/jimmindev/ai-deep-monitor-client-kit/releases/latest/download/ai-deep-monitor-client-kit.tar.gz
tar -xzf ai-deep-monitor-client-kit.tar.gz
cd ai-deep-monitor-client-kit
chmod +x ./*.sh
./install-client.sh
```

Docker est installe automatiquement s'il est absent sur Ubuntu, Debian, Linux
Mint, Fedora, RHEL, Rocky Linux, AlmaLinux et CentOS.

Le kit detecte automatiquement `linux/amd64` sur un PC Linux x64 et
`linux/arm64` sur un NVIDIA Jetson ou un serveur ARM64.

## Installation rapide Windows

Apres extraction de l'archive Windows, ouvrir PowerShell dans le dossier
`ai-deep-monitor-client-kit`:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install-client.ps1 -AppVersion v0.1.4
```

Docker Desktop est installe automatiquement avec `winget` s'il est absent.
Il doit fonctionner en mode **Linux containers**. Le script s'arrete avec une
instruction explicite si Docker Desktop utilise les conteneurs Windows.

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

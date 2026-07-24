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

Pour retirer les anciens dossiers et archives versionnes sans toucher a
l'application ni a ses donnees:

```bash
cd ~/aidp/ai-deep-monitor-client-kit
chmod +x cleanup-old-kits.sh
./cleanup-old-kits.sh
```

Sous Windows, utiliser `.\cleanup-old-kits.ps1` depuis le dossier extrait.

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
.\install-client.ps1 -AppVersion v0.1.5
```

Docker Desktop est installe automatiquement avec `winget` s'il est absent.
Il doit fonctionner en mode **Linux containers**. Le script s'arrete avec une
instruction explicite si Docker Desktop utilise les conteneurs Windows.

Pendant l'installation, renseignez votre utilisateur GitHub et un token
autorise a lire les packages prives. Le site utilise automatiquement le port
`80`, ou le port `8080` lorsque `80` est deja occupe.

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

## Corriger une connexion apres mise a jour

Si la console du navigateur affiche une erreur `500` sur
`/api/auth/login`, telechargez de nouveau le kit `v0.1.7` puis relancez sa
mise a jour. Cette operation repare la configuration d'authentification sans
supprimer les comptes ni les donnees SQL:

```bash
cd ~/aidp
curl -fL \
  -o ai-deep-monitor-client-kit.tar.gz \
  "https://github.com/jimmindev/ai-deep-monitor-client-kit/releases/download/v0.1.7/ai-deep-monitor-client-kit.tar.gz?$(date +%s)"
tar -xzf ai-deep-monitor-client-kit.tar.gz
cd ai-deep-monitor-client-kit
chmod +x ./*.sh
./update-client.sh \
  --install-dir "$HOME/ai-deep-monitor" \
  --app-version v0.1.5 \
  --yes
```

Adaptez `--install-dir` si l'application a ete installee ailleurs. Le message
`401` de `/api/auth/refresh` avant connexion est normal lorsqu'aucune session
n'existe encore. Sur une installation sans compte administrateur, le script
affiche les identifiants initiaux generes; un compte existant conserve son mot
de passe.

Consultez `README.md` pour les options, la restauration et le diagnostic.

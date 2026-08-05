# AI Deep Monitor - Client Kit

Kit public d'installation, de mise a jour et de maintenance d'AI Deep Monitor.
Il ne contient pas les sources React ou API de l'application, uniquement
l'agent terminal local restreint. L'application est livree sous forme d'images
Docker privees publiees sur GHCR.

Le kit suit un canal permanent sans numero de version propre. La version
applicative stable installee par defaut est `v0.1.16`.

Le guide pas a pas est disponible dans
[docs/installation.md](docs/installation.md).

## Organisation du depot

```text
ai-deep-monitor-client-kit/
|-- ai-deep-monitor.sh       # point d'entree Linux et Jetson
|-- AI-Deep-Monitor.cmd      # double-clic Windows vers le menu
|-- ai-deep-monitor.ps1      # point d'entree PowerShell
|-- deploy/                  # definition Docker Compose
|-- docs/                    # guide d'installation
|-- host_terminal_agent/     # agent local restreint Windows/Linux/Jetson
|-- scripts/                 # implementation interne Linux et Windows
|-- tests/                   # tests de non-regression du kit
|-- CHANGELOG.md
`-- README.md
```

Pour une utilisation normale, ne lancez que `ai-deep-monitor.sh` ou
`AI-Deep-Monitor.cmd`. Les fichiers de `scripts/` sont internes au kit.

## Telechargement

- Depot public:
  [github.com/jimmindev/ai-deep-monitor-client-kit](https://github.com/jimmindev/ai-deep-monitor-client-kit)
- Installateur permanent:
  [github.com/jimmindev/ai-deep-monitor-client-kit/releases/latest](https://github.com/jimmindev/ai-deep-monitor-client-kit/releases/latest)
- Linux:
  [ai-deep-monitor-client-kit.tar.gz](https://github.com/jimmindev/ai-deep-monitor-client-kit/releases/download/latest/ai-deep-monitor-client-kit.tar.gz)
- Windows:
  [ai-deep-monitor-client-kit.zip](https://github.com/jimmindev/ai-deep-monitor-client-kit/releases/download/latest/ai-deep-monitor-client-kit.zip)

Les deux archives utilisent toujours le meme dossier racine
`ai-deep-monitor-client-kit`. Elles ne dispersent pas leurs fichiers dans le
dossier courant et une mise a jour ne cree aucun dossier versionne.

Le depot peut aussi etre clone sans authentification:

```bash
git clone https://github.com/jimmindev/ai-deep-monitor-client-kit.git
cd ai-deep-monitor-client-kit
```

Le depot du kit est public, mais les images Docker de l'application restent
privees. L'installateur demandera donc un utilisateur GitHub et un token
autorise a lire les packages GHCR.

## Systemes pris en charge

- Windows 10/11 et Windows Server x64 avec PowerShell 5.1 ou plus recent
- Ubuntu, Debian et Linux Mint
- Fedora, RHEL, Rocky Linux, AlmaLinux et CentOS
- Linux `amd64` (`x86_64`)
- Linux `arm64` (`aarch64`), notamment NVIDIA Jetson Nano

Toutes les images du stack sont des images Linux multiarchitectures. Sous
Windows, Docker Desktop doit donc fonctionner en mode **Linux containers**.
Le kit lit la plateforme du moteur Docker et selectionne automatiquement:

| Environnement | Plateforme Docker |
| --- | --- |
| Windows x64 avec Docker Desktop Linux containers | `linux/amd64` |
| Linux x86_64 | `linux/amd64` |
| Linux ARM64 / NVIDIA Jetson | `linux/arm64` |

Un moteur Docker en mode Windows containers ou une architecture non prise en
charge est bloque avant le telechargement des images, avec un diagnostic clair.

Pour une nouvelle installation comme pour une reparation, les ports sont
valides avant le lancement. Le site utilise `80`, puis `8080`, puis le prochain
port libre. L'API utilise `8000`, puis `8001`, puis le prochain port libre. Un
port deja publie par la meme installation est conserve; un port appartenant a
un autre service est remplace et le fichier `.env` est actualise.

## Prerequis

- Acces Internet pendant l'installation
- Token GitHub autorise a lire les packages prives `ghcr.io`
- Droits administrateur Windows, ou `root`/`sudo` sous Linux
- Espace disque suffisant pour MySQL, les images et le modele Ollama

Docker est verifie automatiquement. S'il est absent:

- Windows: Docker Desktop est installe avec `winget`
- Linux: Docker Engine et Compose v2 sont installes depuis le depot officiel
  Docker de la distribution

## Terminal hote protege

Le kit installe aussi l'agent local necessaire au menu **Serveur > Terminal**.
Il s'execute avec des droits standard, sans port reseau supplementaire, et ne
recoit jamais le mot de passe AI Deep Monitor. Les commandes autorisees sont
controlees par l'API puis une seconde fois par l'agent hote.

- Windows: tache planifiee a droits limites, avec repli sur le demarrage
  utilisateur si la creation de la tache n'est pas autorisee.
- Linux et Jetson: service systemd non-root, sans capacite Linux et avec un
  systeme de fichiers protege.
- Python 3 est installe automatiquement si la machine ne le fournit pas deja.
- Les sauvegardes de securite creees par la mise a jour integree restent dans
  l'espace prive de l'agent; elles ne necessitent aucun droit d'ecriture dans
  le dossier personnel protege par systemd.

Une desinstallation partielle conserve l'agent pour permettre une reparation
rapide. Une desinstallation complete le retire avec l'application.

## Installation Linux

Telecharger puis extraire l'archive:

```bash
mkdir -p ~/aidp
cd ~/aidp
curl -fL \
  -o ai-deep-monitor-client-kit.tar.gz \
  https://github.com/jimmindev/ai-deep-monitor-client-kit/releases/download/latest/ai-deep-monitor-client-kit.tar.gz
tar -xzf ai-deep-monitor-client-kit.tar.gz
cd ai-deep-monitor-client-kit
```

Lancer ensuite l'outil unique:

```bash
chmod +x ./*.sh
./ai-deep-monitor.sh
```

Le menu affiche un numero devant chaque action. Saisissez ce numero puis
validez avec `Entree`; `0` quitte ou revient au menu precedent. Le menu reste
ouvert apres chaque action, y compris lorsqu'une commande affiche une erreur.
Le dossier d'installation par defaut est `~/ai-deep-monitor`.

Dans le gestionnaire de sauvegardes, **Supprimer une selection** affiche les
archives avec leur numero et leur taille. Saisissez un ou plusieurs numeros,
par exemple `1,3,5-7`, puis validez avec `Entree`. Une confirmation explicite
reste obligatoire avant la suppression.

Installation personnalisee:

```bash
./ai-deep-monitor.sh --install-dir /opt/ai-deep-monitor
```

L'utilisation de `/opt` demande que le dossier soit accessible en ecriture.
Le dossier utilisateur par defaut reste le choix le plus simple.

## Installation Windows

Telecharger et extraire l'archive ZIP depuis la
[derniere release](https://github.com/jimmindev/ai-deep-monitor-client-kit/releases/latest),
puis double-cliquer sur `AI-Deep-Monitor.cmd`. Le menu s'ouvre directement.
PowerShell reste disponible si les doubles-clics sont bloques:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\ai-deep-monitor.ps1
```

Le menu affiche un numero devant chaque action. Saisissez ce numero puis
validez avec `Entree`; `0` quitte ou revient au menu precedent. Il revient
automatiquement apres chaque action. Le dossier par defaut est
`C:\ai-deep-monitor`.

Le gestionnaire de sauvegardes Windows utilise la meme selection numerique:
les archives peuvent etre choisies par numeros ou plages, par exemple
`1,3,5-7`.

Pour un chemin personnalise:

```powershell
.\ai-deep-monitor.ps1 -InstallDir "D:\AI-Deep-Monitor"
```

## Acces

Avec les ports par defaut:

```text
Application: http://localhost
API health : http://localhost:8000/health
```

Les ports retenus sont enregistres dans le fichier `.env` de l'installation.
La plateforme detectee y est egalement conservee dans `DOCKER_PLATFORM`.

## Reprise d'une installation

L'installateur conserve un `.env` existant et reutilise les volumes Docker.
S'il detecte des volumes de donnees sans leur ancien `.env`, il s'arrete pour
eviter de rendre la base MySQL inaccessible avec de nouveaux secrets.

Ne supprimez jamais `.env` sans sauvegarde.

## Outil unique Linux et Windows

Le meme point d'entree pilote toute l'installation:

```bash
~/ai-deep-monitor/ai-deep-monitor.sh
```

```powershell
C:\ai-deep-monitor\ai-deep-monitor.ps1
```

Il est aussi utilisable sans menu:

```bash
~/ai-deep-monitor/ai-deep-monitor.sh status
~/ai-deep-monitor/ai-deep-monitor.sh logs
~/ai-deep-monitor/ai-deep-monitor.sh backup
~/ai-deep-monitor/ai-deep-monitor.sh backups list
~/ai-deep-monitor/ai-deep-monitor.sh update
```

```powershell
C:\ai-deep-monitor\ai-deep-monitor.ps1 -Command status
C:\ai-deep-monitor\ai-deep-monitor.ps1 -Command logs
C:\ai-deep-monitor\ai-deep-monitor.ps1 -Command backup
C:\ai-deep-monitor\ai-deep-monitor.ps1 -Command backups -BackupAction List
C:\ai-deep-monitor\ai-deep-monitor.ps1 -Command update
```

La verification est automatique, mais l'installation de la mise a jour reste
manuelle. Le script de mise a jour cree une sauvegarde avant tout changement.

## Verification et mise a jour

Linux:

```bash
~/ai-deep-monitor/ai-deep-monitor.sh update
```

Windows:

```powershell
C:\ai-deep-monitor\ai-deep-monitor.ps1 -Command update
```

La mise a jour conserve les comptes, les volumes MySQL, les donnees
applicatives et les ports de l'installation existante.

## Sauvegarde

Linux:

```bash
~/ai-deep-monitor/ai-deep-monitor.sh backup
```

Windows:

```powershell
C:\ai-deep-monitor\ai-deep-monitor.ps1 -Command backup
```

La sauvegarde contient MySQL, les donnees API, les MIB importees et les
sauvegardes applicatives. Le modele Ollama n'est pas inclus et sera
retelcharge si necessaire.

Les mises a jour normales et les desinstallations completes creent aussi une
sauvegarde de securite. Ces archives externes sont conservees jusqu'a une
action explicite de l'utilisateur.

Pour les lister, conserver uniquement les cinq plus recentes ou toutes les
supprimer:

```bash
~/ai-deep-monitor/ai-deep-monitor.sh backups list
~/ai-deep-monitor/ai-deep-monitor.sh backups prune 5
~/ai-deep-monitor/ai-deep-monitor.sh backups delete-all
```

```powershell
C:\ai-deep-monitor\ai-deep-monitor.ps1 -Command backups -BackupAction List
C:\ai-deep-monitor\ai-deep-monitor.ps1 -Command backups -BackupAction Prune -KeepBackups 5
C:\ai-deep-monitor\ai-deep-monitor.ps1 -Command backups -BackupAction DeleteAll
```

La suppression totale exige une confirmation renforcee. Le guide detaille
quand une archive est creee et la politique de retention recommandee.

## Restauration

Linux:

```bash
~/ai-deep-monitor/ai-deep-monitor.sh restore \
  ~/ai-deep-monitor-backups/ai-deep-monitor-v0.1.16-DATE.tar.gz
```

Windows:

```powershell
C:\ai-deep-monitor\ai-deep-monitor.ps1 -Command restore
```

Linux accepte les sauvegardes `.tar.gz` du kit Linux et les archives `.zip`
produites sous Windows.

## Desinstallation

Partielle, en conservant les volumes et les fichiers:

```bash
~/ai-deep-monitor/ai-deep-monitor.sh uninstall
```

```powershell
C:\ai-deep-monitor\ai-deep-monitor.ps1 -Command uninstall
```

Complete, avec sauvegarde automatique avant suppression:

```bash
~/ai-deep-monitor/ai-deep-monitor.sh purge
```

```powershell
C:\ai-deep-monitor\ai-deep-monitor.ps1 -Command purge
```

La commande `purge` exige la saisie de `SUPPRIMER`, cree une sauvegarde hors
du dossier d'installation, puis retire les conteneurs, les volumes MySQL et
applicatifs, les images Docker du stack et les fichiers d'installation.

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

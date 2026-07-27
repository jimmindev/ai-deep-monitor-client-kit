# AI Deep Monitor - Installation client

Ce kit installe et maintient AI Deep Monitor avec Docker sans livrer les
sources React ou Python. Pour une utilisation normale, lancez uniquement
`ai-deep-monitor.sh` sous Linux ou `ai-deep-monitor.ps1` sous Windows.

## Telechargement

Telechargez la derniere archive depuis la page publique:

[Derniere version du Client Kit](https://github.com/jimmindev/ai-deep-monitor-client-kit/releases/latest)

- Windows: `ai-deep-monitor-client-kit.zip`
- Linux ou NVIDIA Jetson: `ai-deep-monitor-client-kit.tar.gz`

Les deux archives utilisent toujours le dossier `ai-deep-monitor-client-kit`.
Le kit demande un utilisateur GitHub et un token autorise a lire les images
privees de l'application sur `ghcr.io`.

## Installation Windows

1. Extrayez `ai-deep-monitor-client-kit.zip`.
2. Ouvrez PowerShell dans le dossier extrait.
3. Executez:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\ai-deep-monitor.ps1
```

Selectionnez **Installer ou reparer** avec les fleches, puis validez avec
`Entree`. Le menu reste ouvert apres l'operation ou apres une erreur. Le
dossier d'installation par defaut est `C:\ai-deep-monitor`.

Docker Desktop est installe avec `winget` s'il est absent. Il doit utiliser le
mode **Linux containers**.

## Installation Linux ou NVIDIA Jetson

```bash
mkdir -p ~/aidp
cd ~/aidp
curl -fL \
  -o ai-deep-monitor-client-kit.tar.gz \
  https://github.com/jimmindev/ai-deep-monitor-client-kit/releases/latest/download/ai-deep-monitor-client-kit.tar.gz
tar -xzf ai-deep-monitor-client-kit.tar.gz
cd ai-deep-monitor-client-kit
chmod +x ./*.sh
./ai-deep-monitor.sh
```

Selectionnez **Installer ou reparer** avec les fleches, puis validez avec
`Entree`. Le menu reste ouvert apres l'operation ou apres une erreur. La
touche `Q` permet de quitter. Le dossier d'installation par defaut est
`~/ai-deep-monitor`.

Docker Engine et Compose v2 sont installes s'ils sont absents. Le kit choisit
automatiquement `linux/amd64` sur PC x64 et `linux/arm64` sur NVIDIA Jetson.

## Ports

Le kit controle les ports avant chaque installation ou reparation:

- interface web: `80`, puis `8080`, puis le prochain port libre;
- API: `8000`, puis `8001`, puis le prochain port libre.

Un port deja utilise par cette installation est conserve. Un port appartenant
a un autre service est remplace automatiquement. L'adresse finale est affichee
a la fin de l'installation.

## Menu de maintenance

Relancez le meme outil depuis le dossier d'installation:

```bash
~/ai-deep-monitor/ai-deep-monitor.sh
```

```powershell
C:\ai-deep-monitor\ai-deep-monitor.ps1
```

Le menu actuel propose:

1. installer ou reparer;
2. verifier et installer une mise a jour;
3. afficher l'etat des services;
4. demarrer l'application;
5. arreter l'application;
6. creer une sauvegarde;
7. gerer les sauvegardes;
8. restaurer une sauvegarde;
9. afficher les journaux;
10. desinstaller les conteneurs en conservant les donnees;
11. tout supprimer.

## Sauvegardes

Une sauvegarde complete contient la base MySQL et les donnees applicatives,
notamment les MIB et les fichiers geres par l'API. Elle est stockee hors du
dossier d'installation:

- Linux: `~/ai-deep-monitor-backups` par defaut;
- Windows: `C:\ai-deep-monitor-backups` par defaut.

Le kit cree une sauvegarde:

- quand l'utilisateur choisit **Creer une sauvegarde**;
- avant une mise a jour normale;
- avant une desinstallation complete.

Une installation neuve, une reparation sans changement de version et une
desinstallation partielle n'ajoutent pas d'archive complete.

Les sauvegardes ne sont jamais supprimees silencieusement. Le choix
**7. Gerer les sauvegardes** permet de:

- afficher leur date et leur taille;
- conserver uniquement les N archives les plus recentes;
- choisir une ou plusieurs archives precises a supprimer;
- supprimer toutes les archives avec une confirmation explicite.

Pour une suppression ciblee, naviguez avec les fleches, cochez ou decochez
chaque archive avec `Espace`, puis validez avec `Entree`. La touche `Q` annule
la selection. Si le terminal ne prend pas en charge ce mode, saisissez les
numeros ou les plages demandes, par exemple `1,3,5-7`.

Commandes directes:

```bash
~/ai-deep-monitor/ai-deep-monitor.sh backups list
~/ai-deep-monitor/ai-deep-monitor.sh backups prune 5
~/ai-deep-monitor/ai-deep-monitor.sh backups delete-selected
~/ai-deep-monitor/ai-deep-monitor.sh backups delete-all
```

```powershell
C:\ai-deep-monitor\ai-deep-monitor.ps1 -Command backups -BackupAction List
C:\ai-deep-monitor\ai-deep-monitor.ps1 -Command backups -BackupAction Prune -KeepBackups 5
C:\ai-deep-monitor\ai-deep-monitor.ps1 -Command backups -BackupAction DeleteSelected
C:\ai-deep-monitor\ai-deep-monitor.ps1 -Command backups -BackupAction DeleteAll
```

La politique conseillee est de conserver au minimum les trois dernieres
sauvegardes validees et une copie externe recente.

## Desinstallation

### Partielle

Le choix **10** retire les conteneurs et le reseau. Il conserve les volumes
MySQL et applicatifs, les images Docker, `.env`, le dossier d'installation et
les sauvegardes.

### Complete

Le choix **11. TOUT SUPPRIMER** cree d'abord une sauvegarde externe, puis
supprime les conteneurs, les volumes, les images du stack et le dossier
d'installation. La sauvegarde externe est volontairement conservee. Utilisez
ensuite le gestionnaire de sauvegardes si sa suppression est reellement
souhaitee.

## Diagnostic

Le choix **3** affiche l'etat des services et le choix **9** leurs journaux.
Si l'API ne devient pas saine, l'installateur affiche automatiquement les
derniers journaux de MySQL, Ollama, de la sandbox et de l'API.

Une erreur `401` sur `/api/auth/refresh` avant connexion est normale sans
session existante. Une erreur `500` sur `/api/auth/login` ne l'est pas.

## Securite des donnees

- Les sources de l'application ne sont pas presentes dans le kit.
- Les secrets sont generes sur la machine du client.
- Une installation existante conserve ses comptes et ses volumes.
- Ne supprimez jamais `.env` ou les volumes Docker sans sauvegarde validee.
- Si des volumes SQL existent mais que `.env` a disparu, l'installation
  s'arrete pour ne pas rendre la base inaccessible.

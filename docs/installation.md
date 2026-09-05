# AI Deep Monitor - Installation client

Ce kit installe et maintient AI Deep Monitor avec Docker sans livrer les
sources React ou API de l'application. Pour une utilisation normale, lancez
uniquement `ai-deep-monitor.sh` sous Linux/Jetson ou double-cliquez sur
`AI-Deep-Monitor.cmd` sous Windows.

Le kit installe egalement l'agent local du terminal de diagnostic. Cet agent
reste separe des conteneurs, s'execute sans droits administrateur et applique
la meme politique restrictive sous Windows, Linux et NVIDIA Jetson. Python 3
est installe automatiquement si necessaire.

## Telechargement

Telechargez la derniere archive depuis la page publique:

[Derniere version du Client Kit](https://github.com/jimmindev/ai-deep-monitor-client-kit/releases/latest)

- Windows: `ai-deep-monitor-client-kit.zip`
- Linux ou NVIDIA Jetson: `ai-deep-monitor-client-kit.tar.gz`

Les deux archives utilisent toujours le dossier `ai-deep-monitor-client-kit`.
Le kit demande un utilisateur GitHub et un token autorise a lire les images
privees de l'application sur `ghcr.io`.
Cette saisie est obligatoire pour chaque installation ou reparation lancee
normalement, meme si Docker possede deja une session en cache. Le token est
valide sur les images API et frontend avant d'etre conserve. L'option technique
sans connexion n'est acceptee qu'avec `--no-start`/`-NoStart` pour les tests et
ne peut pas installer une application utilisable.

## Installation Windows

1. Extrayez `ai-deep-monitor-client-kit.zip`.
2. Double-cliquez sur `AI-Deep-Monitor.cmd`.

Le lanceur ouvre directement le menu. Si l'ouverture par double-clic est
bloquee par une politique d'entreprise, ouvrez PowerShell dans le dossier
extrait puis executez:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\ai-deep-monitor.ps1
```

Saisissez le numero de **Installer ou reparer**, puis validez avec `Entree`.
Le menu reste ouvert apres l'operation ou apres une erreur. Le
dossier d'installation par defaut est `C:\ai-deep-monitor`.

Docker Desktop est installe avec `winget` s'il est absent. Il doit utiliser le
mode **Linux containers**. Un GPU NVIDIA n'est pas obligatoire: l'installateur
teste CUDA dans Docker et choisit automatiquement le profil `nvidia` ou `cpu`.

## Installation Linux ou NVIDIA Jetson

```bash
mkdir -p ~/aidp
cd ~/aidp
curl -fL \
  -o ai-deep-monitor-client-kit.tar.gz \
  https://github.com/jimmindev/ai-deep-monitor-client-kit/releases/download/latest/ai-deep-monitor-client-kit.tar.gz
tar -xzf ai-deep-monitor-client-kit.tar.gz
cd ai-deep-monitor-client-kit
chmod +x ./*.sh
./ai-deep-monitor.sh
```

Saisissez le numero de **Installer ou reparer**, puis validez avec `Entree`.
Le menu reste ouvert apres l'operation ou apres une erreur. Le choix `0`
permet de quitter. Le dossier d'installation par defaut est
`~/ai-deep-monitor`.

Docker Engine et Compose v2 sont installes s'ils sont absents. Le kit choisit
automatiquement `linux/amd64` sur PC x64 et `linux/arm64` sur NVIDIA Jetson.
Il selectionne ensuite `nvidia`, `jetson` ou `cpu`, valide le runtime dans un
conteneur et conserve ce profil pendant les mises a jour. Sur un PC NVIDIA, il
teste l'image CUDA officielle. Sur Jetson, il evite cette image generique et
compile directement une image locale pour la version CUDA de JetPack et
l'architecture GPU detectees. Une image personnalisee ou locale deja presente
est testee et reutilisee. En dernier recours, le mode automatique utilise le CPU
au lieu de bloquer toute l'application.

Forcer un profil ou demander une nouvelle detection:

```bash
~/ai-deep-monitor/update-client.sh --llama-profile cpu
~/ai-deep-monitor/update-client.sh --redetect-llama-runtime
~/ai-deep-monitor/update-client.sh --llama-profile jetson --require-gpu
```

Sous Windows:

```powershell
C:\ai-deep-monitor\update-client.ps1 -LlamaProfile cpu
C:\ai-deep-monitor\update-client.ps1 -RedetectLlamaRuntime
C:\ai-deep-monitor\update-client.ps1 -LlamaProfile nvidia -RequireGpu
```

Pour une version CUDA non encore repertoriee, definissez dans `.env`
`LLAMA_CPP_CUDA_DEVEL_IMAGE` et `LLAMA_CPP_CUDA_RUNTIME_IMAGE` avec deux bases
`nvidia/cuda` compatibles. `LLAMA_CPP_AUTO_BUILD_CUDA=false` desactive la
construction locale et force le repli CPU en mode automatique.

### Premiere installation Jetson

La construction locale de llama.cpp est volontairement effectuee une seule
fois. Elle utilise quatre taches par defaut pour limiter la consommation de RAM
partagee. Sur une petite machine, ajoutez cette ligne dans
`~/ai-deep-monitor/.env` avant de relancer l'installation:

```env
LLAMA_CPP_CUDA_BUILD_JOBS=2
```

Pour imposer CUDA et refuser tout repli CPU:

```bash
~/ai-deep-monitor/install-client.sh --llama-profile jetson --require-gpu
```

Prevoir au minimum 20 Go libres pour les images, le cache de construction et le
modele. Sur le Jetson Orin de validation, caches vides, le temps mesure a ete:

| Etape | Temps mesure |
| --- | ---: |
| Construction locale llama.cpp CUDA | 31 min 59 s |
| Images applicatives, modele, MySQL et demarrage | 13 min 58 s |
| Installation propre avec le correctif | environ 46 a 48 min |

Une desinstallation complete avec suppression des images et du cache impose de
reconstruire llama.cpp. Une mise a jour normale conserve l'image locale et le
volume du modele: elle ne doit donc pas reprendre ces 46 a 48 minutes.

Pendant la construction, la ligne attendue contient `Construction locale de
llama.cpp`. Le kit ne doit plus commencer par telecharger l'image generique
`server-cuda`. Apres le demarrage:

```bash
~/ai-deep-monitor/verify-llama-gpu.sh
docker ps --filter name=ai-monitor-client
curl -fsS http://127.0.0.1:8000/health
```

La verification doit afficher un device `CUDA0` et les services API, MySQL,
llama.cpp et sandbox doivent etre `healthy`.

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
2. verifier et installer une mise a jour de l'application, du Client Kit et du
   terminal hote;
3. afficher l'etat des services;
4. demarrer l'application;
5. arreter l'application;
6. creer une sauvegarde;
7. gerer les sauvegardes;
8. restaurer une sauvegarde;
9. afficher les journaux;
10. reparer et verifier le terminal hote;
11. desinstaller les conteneurs en conservant les donnees;
12. tout supprimer.

Avant de modifier les conteneurs, l'action 2 telecharge la release permanente
`latest`, verifie la somme SHA256 publiee, puis remplace les installateurs,
scripts Windows/Linux, fichiers Compose, documentation et fichiers de l'agent
terminal. La sauvegarde et la mise a jour des images applicatives commencent
ensuite avec ces nouveaux outils. L'action reste donc utile si la version de
l'application n'a pas change.

Pour la transition, un poste qui possede une ancienne version du Client Kit
doit telecharger et extraire une seule fois l'archive `latest`, puis lancer
**Installer ou reparer** ou **Mettre a jour**. A partir de cette version, les
prochaines mises a jour synchronisent aussi automatiquement les fichiers
d'installation.

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

Pour une suppression ciblee, saisissez les numeros ou les plages demandes,
par exemple `1,3,5-7`. Une saisie vide annule la selection.

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

Le choix **11** retire les conteneurs et le reseau. Il conserve les volumes
MySQL et applicatifs, les images Docker, `.env`, le dossier d'installation et
les sauvegardes.

### Complete

Le choix **12. TOUT SUPPRIMER** cree d'abord une sauvegarde externe, puis
supprime les conteneurs, les volumes, les images du stack et le dossier
d'installation. La sauvegarde externe est volontairement conservee. Utilisez
ensuite le gestionnaire de sauvegardes si sa suppression est reellement
souhaitee.

## Diagnostic

Le choix **3** affiche l'etat des services et le choix **9** leurs journaux.
Le choix **10** reinstalle le terminal hote et verifie immediatement son signal.
Sous Linux/Jetson, un echec affiche aussi les dernieres lignes de `systemd`.
Si l'API ne devient pas saine, l'installateur affiche automatiquement les
derniers journaux de MySQL, llama.cpp, de la sandbox et de l'API.

Une erreur `401` sur `/api/auth/refresh` avant connexion est normale sans
session existante. Une erreur `500` sur `/api/auth/login` ne l'est pas.

## Securite des donnees

- Les sources de l'application ne sont pas presentes dans le kit.
- Les secrets sont generes sur la machine du client.
- Les images API et frontend refusent les telechargements anonymes.
- Sous Linux, `.env` reste en mode `600`; sous Windows, ses ACL sont limitees au
  compte courant, au systeme et aux administrateurs.
- Une installation existante conserve ses comptes et ses volumes.
- Ne supprimez jamais `.env` ou les volumes Docker sans sauvegarde validee.
- Si des volumes SQL existent mais que `.env` a disparu, l'installation
  s'arrete pour ne pas rendre la base inaccessible.

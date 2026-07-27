# Historique des versions du Client Kit

## v0.1.9 - 2026-07-27

### Ajoute

- Selection multiple des sauvegardes a supprimer sous Linux, NVIDIA Jetson et
  Windows.
- Navigation avec les fleches, coche avec Espace, validation avec Entree et
  annulation avec Q.
- Selection de secours par numeros et plages, par exemple `1,3,5-7`, pour les
  terminaux sans mode interactif.
- Commandes de suppression ciblee utilisables dans les tests et les procedures
  d'administration.

### Securise

- Confirmation explicite avant toute suppression ciblee.
- Resolution exacte du nom des archives afin de ne jamais supprimer une
  sauvegarde seulement parce que son nom ressemble a la selection.
- Tests de non-regression verifiant que les archives non selectionnees sont
  conservees.

## v0.1.8 - 2026-07-27

### Ajoute

- Menus interactifs Linux, NVIDIA Jetson et Windows pilotes avec les fleches
  du clavier et la touche Entree.
- Racine du depot simplifiee autour des deux lanceurs client.
- Gestionnaire de sauvegardes Linux et Windows permettant de lister les
  archives, de conserver uniquement les N plus recentes ou de toutes les
  supprimer avec confirmation renforcee.
- Scripts internes ranges par plateforme dans `scripts/`, avec Docker Compose,
  documentation et notes de version dans des dossiers dedies.
- Lanceur Windows unique `ai-deep-monitor.ps1` avec le meme menu de
  maintenance que Linux.
- Lanceur Linux unique `ai-deep-monitor.sh` avec menu pour l'installation, la
  mise a jour, le diagnostic, la sauvegarde, la restauration et la
  desinstallation.
- Mode `TOUT SUPPRIMER` protege par confirmation, avec sauvegarde externe avant
  suppression des conteneurs, volumes SQL et applicatifs, images et fichiers.

### Corrige

- Le lanceur interactif reste ouvert apres chaque action et apres les erreurs.
- La detection des ports Windows distingue maintenant un port publie par
  l'installation active d'un port occupe par un autre service.
- En cas d'echec du stack sous Windows, les journaux MySQL, sandbox, Ollama et
  API sont affiches directement.
- Les ports d'une installation existante sont maintenant revalides avant le
  demarrage, au meme titre qu'une installation neuve.
- Le site essaie `80`, puis `8080`, puis les ports suivants; l'API essaie
  `8000`, puis `8001`, puis les ports suivants.
- Un port deja utilise par le meme projet Docker est conserve, tandis qu'un
  port appartenant a un autre service est remplace automatiquement.
- En cas d'API non saine, l'installateur affiche directement l'etat et les
  journaux des services utiles.

### Validation

- Tests Shell de syntaxe, de plateforme, de port occupe et de selection des
  ports de repli.
- Installation et mise a jour sans demarrage Docker avec conservation de
  l'application `v0.1.5`.

## v0.1.7 - 2026-07-24

### Ajoute

- Detection de la plateforme du moteur Docker avant tout lancement.
- Selection automatique de `linux/amd64` sur Windows Docker Desktop et Linux
  x86_64.
- Selection automatique de `linux/arm64` sur NVIDIA Jetson et Linux ARM64.
- Persistance de la plateforme retenue dans `DOCKER_PLATFORM`.
- Test de non-regression des architectures et du mode de conteneurs Docker.

### Securise

- Blocage explicite de Docker Desktop en mode Windows containers.
- Blocage des architectures non publiees au lieu de laisser Docker executer
  une image emulee ou incompatible.
- Plateforme verrouillee pour MySQL, API, Ollama et frontend dans Compose.

### Corrige

- Une mise a jour du Client Kit recharge les images multiarchitectures meme si
  la version applicative reste identique.
- La configuration d'authentification de l'API est maintenant generee et
  conservee dans `.env`; l'absence de `AUTH_SECRET_KEY` ne provoque plus une
  erreur HTTP 500 lors de la connexion.
- Le script de mise a jour repare automatiquement une ancienne installation
  dont les variables `AUTH_*` sont absentes, meme lorsque les versions du kit
  et de l'application n'ont pas change.
- La reparation de l'authentification conserve les volumes MySQL, les comptes,
  les mots de passe existants et les ports deja selectionnes.
- Le service sandbox et les parametres de retention de telemetrie de
  l'application `v0.1.5` sont maintenant presents dans le Compose client.
- Une nouvelle installation utilise le port web `80` lorsqu'il est libre,
  sinon le port `8080`; elle s'arrete clairement si les deux sont occupes.
- Les archives de distribution portent maintenant un nom stable et
  s'extraient toujours dans `ai-deep-monitor-client-kit`, sans creer un
  nouveau dossier pour chaque version.
- Un nettoyeur de transition avait ete fourni pour les anciens dossiers
  versionnes. Il a depuis ete retire du kit courant.

### Validation

- Installation neuve Linux et Windows sans demarrage.
- Reparation d'un `.env` existant avec conservation du mot de passe MySQL et
  du port web.
- Validation Docker Compose apres generation des secrets.
- Validation syntaxique des scripts Shell et PowerShell.

### Versions

- Client Kit: `v0.1.7`.
- Application installee par defaut: `v0.1.5`.

## v0.1.6 - 2026-07-24

### Corrige

- La detection des ports Linux ne tente plus d'ouvrir elle-meme les ports
  privilegies inferieurs a `1024`.
- Une execution avec un utilisateur non privilegie ne confond plus
  `Permission denied` avec `Port deja utilise`.
- L'installation peut de nouveau selectionner automatiquement le port `80`
  lorsqu'il est libre, notamment sur Ubuntu et NVIDIA Jetson.
- La detection des ports occupes s'appuie en priorite sur les sockets TCP
  reellement en ecoute via `ss`, puis `/proc/net/tcp` et `/proc/net/tcp6`.

### Validation

- Test de selection du port `80` avec un utilisateur Linux non privilegie.
- Test de distinction entre un port occupe et le prochain port libre.
- Tests de non-regression des installations Linux et Windows sans demarrage.
- Validation syntaxique des scripts Shell et PowerShell.

### Versions

- Client Kit: `v0.1.6`.
- Application installee par defaut: `v0.1.4`.

## v0.1.5 - 2026-07-24

### Ajoute

- Installation Linux complete pour Debian, Ubuntu, Linux Mint, Fedora, RHEL,
  Rocky Linux, AlmaLinux et CentOS.
- Detection et installation automatique de Docker Engine et Compose v2 depuis
  les depots officiels Docker.
- Detection de Docker Desktop sous Windows et installation automatique via
  `winget` lorsqu'il est absent.
- Scripts Linux de verification de version, mise a jour, sauvegarde,
  restauration et desinstallation.
- Selection automatique des ports disponibles sous Linux.
- Sauvegarde Linux au format `.tar.gz` avec checksum SHA-256.
- Restauration Linux des archives `.tar.gz` et des sauvegardes `.zip` Windows.
- Controle contre la traversee de chemins lors de l'extraction d'une sauvegarde.
- Detection des volumes existants et blocage protecteur lorsqu'un `.env` est
  absent.

### Modifie

- Le kit est versionne independamment de l'application.
- La version applicative par defaut reste `v0.1.4`.
- Les documentations Windows et Linux sont rassemblees et detaillees.
- Les scripts installes sont synchronises pour les deux systemes.

### Securite

- Les secrets Linux et les sauvegardes sont limites a l'utilisateur courant.
- Docker est installe depuis des depots signes, sans execution de script
  distant via `curl | sh`.
- Le code source applicatif reste absent du kit.

## v0.1.4 - 2026-07-20

- Ajout d'Ollama au stack Docker client.
- Ajout de la verification de version applicative et de la notification dans
  l'interface.
- Stabilisation du proxy API et du parcours d'authentification client.

## v0.1.3 - 2026-07-15

- Ajout des sauvegardes et restaurations MySQL.
- Ajout des desinstallations partielle et complete.
- Conservation des volumes existants et detection des installations precedentes.

## v0.1.2 - 2026-07-13

- Publication des images privees API et frontend.
- Premier compose client sans code source.

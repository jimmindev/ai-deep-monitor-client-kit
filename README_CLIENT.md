# AI Deep Monitor - Installation client

Ce dossier est le kit client.
Il ne contient pas le code source de l'application.

## Contenu

```text
install-client.ps1          # Installation initiale Windows
check-update.ps1            # Verification automatique des versions
update-client.ps1           # Mise a jour Windows
backup-client.ps1           # Sauvegarde MySQL et donnees API
restore-client.ps1          # Restauration controlee
uninstall-client.ps1        # Desinstallation partielle ou complete
docker-compose.release.yml  # Compose client sans build source
```

## Prerequis client

- Docker Desktop installe et demarre
- Acces au registry prive `ghcr.io`
- Token GitHub avec permission `read:packages`
- Espace disque suffisant pour le modele Ollama telecharge au premier lancement

## Installation simple

Ouvrir PowerShell dans ce dossier :

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install-client.ps1 -AppVersion v0.1.4
```

Les ports sont choisis automatiquement si les ports proposes sont occupes. Une installation existante est reprise sans recreer les secrets ni les volumes. Des volumes existants sans ancien `.env` bloquent volontairement l'installation afin de proteger les donnees MySQL.

Par defaut, l'application est installee dans :

```text
C:\ai-deep-monitor
```

URLs :

```text
Frontend  : http://localhost
API health: http://localhost:8000/health
```

## Installation avec dossier ou ports personnalises

```powershell
.\install-client.ps1 -InstallDir "D:\Apps\ai-deep-monitor" -AppVersion v0.1.4 -FrontendPort 8081 -ApiPort 8001
```

## Mise a jour simple

Verifier automatiquement si une nouvelle version stable est disponible :

```powershell
.\check-update.ps1
```

Mettre a jour automatiquement vers la derniere version stable disponible, avec confirmation manuelle :

```powershell
.\update-client.ps1
```

Le script :

- lit la version installee dans `C:\ai-deep-monitor\.env` ;
- interroge GHCR ;
- compare les tags stables `vX.Y.Z` ;
- annonce la derniere version disponible ;
- demande confirmation avant modification ;
- sauvegarde les donnees avant la mise a jour ;
- modifie `APP_VERSION` dans `.env` ;
- remplace le compose et les scripts installes si le kit contient une version plus recente ;
- telecharge les nouvelles images Docker ;
- relance les services.

## Version visible dans l'application

La barre du haut affiche la version installee.
La version client actuelle est `v0.1.4`. La version `v1.0.0` ne sera publiee qu'une fois l'application fonctionnellement complete et validee.
Si `UPDATE_CHECK_ENABLED=true` et que `UPDATE_CHECK_USER` / `UPDATE_CHECK_TOKEN` sont renseignes dans `.env`, l'API verifie les tags GHCR et l'application affiche une notification quand une nouvelle version stable est disponible.

Le token reste cote serveur dans `C:\ai-deep-monitor\.env`.
Il n'est jamais envoye au navigateur.

Mise a jour forcee vers une version precise :

```powershell
.\update-client.ps1 -AppVersion v0.2.0
```

## Rollback

Revenir a une version precedente :

```powershell
.\update-client.ps1 -AppVersion v0.1.0
```

## Sauvegarde et restauration

Creer un ZIP portable dans `C:\ai-deep-monitor-backups` :

```powershell
.\backup-client.ps1
```

Restaurer MySQL, les donnees API, les MIB et les sauvegardes applicatives :

```powershell
.\restore-client.ps1 -BackupFile "C:\ai-deep-monitor-backups\ai-deep-monitor-v0.1.4-AAAAMMJJ-HHMMSS.zip"
```

Le modele Ollama n'est pas archive : il est retelcharge automatiquement si necessaire.

## Desinstallation

Conserver les donnees et retirer uniquement les conteneurs :

```powershell
.\uninstall-client.ps1 -Mode Partial
```

Sauvegarder puis supprimer l'installation et ses volumes :

```powershell
.\uninstall-client.ps1 -Mode Full
```

## Commandes utiles

```powershell
cd C:\ai-deep-monitor
docker compose -f docker-compose.release.yml --env-file .env ps
docker compose -f docker-compose.release.yml --env-file .env logs -f
docker compose -f docker-compose.release.yml --env-file .env down
docker exec ai-monitor-client-ollama ollama list
```

## Chatbot Ollama

Le kit lance un conteneur `ollama` et telecharge automatiquement le modele defini dans `.env` :

```env
OLLAMA_MODEL=llama3.1
```

Le premier demarrage peut etre long, le temps de telecharger le modele.
Pour changer de modele, modifie `OLLAMA_MODEL`, puis relance `.\update-client.ps1`.

## Securite

Le client ne recoit pas :

- le depot Git ;
- `react/src` ;
- `api/app` ;
- `.env` interne ;
- les donnees de developpement.

Le client execute uniquement les images Docker privees versionnees.

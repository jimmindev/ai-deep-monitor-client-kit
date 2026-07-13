# AI Deep Monitor - Kit d'installation

Cette branche contient uniquement le kit d'installation client/testeur.
Elle ne contient pas le code source React, Python, ni les fichiers internes de developpement.

## Contenu

```text
install-client.ps1          # Installation initiale Windows
check-update.ps1            # Verification automatique des versions
update-client.ps1           # Mise a jour Windows
docker-compose.release.yml  # Compose sans build source
```

## Prerequis

- Docker Desktop installe et demarre
- Acces au registry prive `ghcr.io`
- Token GitHub avec permission `read:packages`
- Espace disque suffisant pour le modele Ollama telecharge au premier lancement

## Installation

Ouvrir PowerShell dans ce dossier :

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install-client.ps1 -AppVersion v0.1.2
```

Par defaut, l'application est installee dans :

```text
C:\ai-deep-monitor
```

URLs par defaut :

```text
Frontend  : http://localhost
API health: http://localhost:8000/health
```

## Installation personnalisee

```powershell
.\install-client.ps1 -InstallDir "D:\Apps\ai-deep-monitor" -AppVersion v0.1.2 -FrontendPort 8081 -ApiPort 8001
```

## Verification de mise a jour

```powershell
.\check-update.ps1
```

Le script lit la version installee dans `C:\ai-deep-monitor\.env`, interroge GHCR, puis indique si une version stable plus recente existe.

## Mise a jour

```powershell
.\update-client.ps1
```

Le script verifie la derniere version stable disponible, demande confirmation, met a jour `APP_VERSION`, remplace le compose installe si le kit contient une version plus recente, telecharge les images Docker et relance les services.

Pour forcer une version precise :

```powershell
.\update-client.ps1 -AppVersion v0.2.0
```

## Rollback

```powershell
.\update-client.ps1 -AppVersion v0.1.0
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

Le kit ne livre pas :

- le depot Git source ;
- `react/src` ;
- `api/app` ;
- `.env` interne ;
- les donnees de developpement.

Le client ou testeur execute uniquement les images Docker privees versionnees.

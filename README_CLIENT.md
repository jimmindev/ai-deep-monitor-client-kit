# AI Deep Monitor - Installation client

Ce dossier est le kit client.
Il ne contient pas le code source de l'application.

## Contenu

```text
install-client.ps1          # Installation initiale Windows
update-client.ps1           # Mise a jour Windows
docker-compose.release.yml  # Compose client sans build source
```

## Prerequis client

- Docker Desktop installe et demarre
- Acces au registry prive `ghcr.io`
- Token GitHub avec permission `read:packages`

## Installation simple

Ouvrir PowerShell dans ce dossier :

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install-client.ps1 -AppVersion v0.1.0
```

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
.\install-client.ps1 -InstallDir "D:\Apps\ai-deep-monitor" -AppVersion v0.1.0 -FrontendPort 8081 -ApiPort 8001
```

## Mise a jour simple

Quand une nouvelle version est annoncee :

```powershell
.\update-client.ps1 -AppVersion v0.2.0
```

Le script modifie `APP_VERSION` dans `.env`, telecharge les nouvelles images Docker et relance les services.

## Rollback

Revenir a une version precedente :

```powershell
.\update-client.ps1 -AppVersion v0.1.0
```

## Commandes utiles

```powershell
cd C:\ai-deep-monitor
docker compose -f docker-compose.release.yml --env-file .env ps
docker compose -f docker-compose.release.yml --env-file .env logs -f
docker compose -f docker-compose.release.yml --env-file .env down
```

## Securite

Le client ne recoit pas :

- le depot Git ;
- `react/src` ;
- `api/app` ;
- `.env` interne ;
- les donnees de developpement.

Le client execute uniquement les images Docker privees versionnees.

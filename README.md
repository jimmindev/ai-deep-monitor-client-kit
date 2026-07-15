# AI Deep Monitor - Kit d'installation

Ce depot contient uniquement le kit d'installation client/testeur.
Elle ne contient pas le code source React, Python, ni les fichiers internes de developpement.

## Contenu

```text
install-client.ps1          # Installation initiale Windows
check-update.ps1            # Verification automatique des versions
update-client.ps1           # Mise a jour Windows
backup-client.ps1           # Sauvegarde MySQL et donnees applicatives
restore-client.ps1          # Restauration controlee d'une sauvegarde
uninstall-client.ps1        # Desinstallation partielle ou complete
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
.\install-client.ps1 -AppVersion v0.1.3
```

Le script choisit automatiquement d'autres ports si `80` ou `8000` sont deja occupes. Il conserve un `.env` et des volumes existants. S'il trouve des volumes sans leur ancien `.env`, il s'arrete pour eviter de rendre MySQL inaccessible avec de nouveaux mots de passe.

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
.\install-client.ps1 -InstallDir "D:\Apps\ai-deep-monitor" -AppVersion v0.1.3 -FrontendPort 8081 -ApiPort 8001
```

## Verification de mise a jour

La version client actuelle est `v0.1.3`. Les versions restent en `v0.x` tant que l'application n'est pas fonctionnellement complete; `v1.0.0` marquera la premiere version finale validee.

```powershell
.\check-update.ps1
```

Le script lit la version installee dans `C:\ai-deep-monitor\.env`, interroge GHCR, puis indique si une version stable plus recente existe.

## Mise a jour

```powershell
.\update-client.ps1
```

Le script verifie la derniere version stable disponible, demande confirmation, effectue une sauvegarde automatique, met a jour `APP_VERSION`, remplace les scripts et le compose installes, telecharge les images Docker et relance les services.

Pour forcer une version precise :

```powershell
.\update-client.ps1 -AppVersion v0.2.0
```

## Rollback

```powershell
.\update-client.ps1 -AppVersion v0.1.0
```

## Sauvegarde

```powershell
.\backup-client.ps1
```

La sauvegarde ZIP est creee par defaut dans `C:\ai-deep-monitor-backups`. Elle contient :

- un dump logique MySQL portable ;
- les dashboards, conversations, profils et regles stockes par l'API ;
- les MIB importees ;
- les sauvegardes applicatives generees.

Le modele Ollama n'est pas inclus car il peut etre retelcharge et occupe plusieurs gigaoctets.

## Restauration

```powershell
.\restore-client.ps1 -BackupFile "C:\ai-deep-monitor-backups\ai-deep-monitor-v0.1.3-20260715-120000.zip"
```

Le checksum du dump est controle avant remplacement des donnees. L'application est arretee pendant l'operation puis relancee automatiquement.

## Desinstallation

Partielle, en conservant volumes, images et configuration :

```powershell
.\uninstall-client.ps1 -Mode Partial
```

Complete, avec sauvegarde automatique avant suppression des volumes et du dossier d'installation :

```powershell
.\uninstall-client.ps1 -Mode Full
```

Pour supprimer egalement les images Docker :

```powershell
.\uninstall-client.ps1 -Mode Full -RemoveImages
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

# AI Deep Monitor Client Kit v0.1.7

Cette version rend l'installation deterministe sur Windows, Linux x86_64 et
Linux ARM64, notamment les NVIDIA Jetson.

## Compatibilite

| Systeme | Plateforme selectionnee |
| --- | --- |
| Windows x64 avec Docker Desktop Linux containers | `linux/amd64` |
| Linux x86_64 | `linux/amd64` |
| Linux ARM64 / NVIDIA Jetson | `linux/arm64` |

Les images applicatives `v0.1.4` ont ete republiees sous forme de manifestes
multiarchitectures `amd64` et `arm64`.

## Nouveau comportement

- L'installateur interroge le moteur Docker, puis enregistre la plateforme
  retenue dans `.env`.
- Compose applique cette plateforme a MySQL, l'API, Ollama et le frontend.
- Docker Desktop en mode Windows containers est refuse avec l'instruction de
  repasser en mode Linux containers.
- Une architecture non prise en charge est refusee avant le telechargement.
- Lors d'un changement de version du kit, les images sont rechargees meme si
  l'application reste en `v0.1.4`.

## Installation Linux et Jetson

```bash
curl -fL \
  -o ai-deep-monitor-client-kit-v0.1.7.tar.gz \
  https://github.com/jimmindev/ai-deep-monitor-client-kit/releases/download/v0.1.7/ai-deep-monitor-client-kit-v0.1.7.tar.gz
tar -xzf ai-deep-monitor-client-kit-v0.1.7.tar.gz
cd ai-deep-monitor-client-kit-v0.1.7
chmod +x ./*.sh
./install-client.sh
```

## Installation Windows

Extraire l'archive ZIP, verifier que Docker Desktop utilise Linux containers,
puis executer:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\install-client.ps1 -AppVersion v0.1.4
```

## Versions

- Client Kit: `v0.1.7`
- Application stable: `v0.1.4`

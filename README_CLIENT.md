# AI Deep Monitor - Guide d'installation client

Ce kit installe et maintient AI Deep Monitor avec Docker, sans livrer les
sources React ou Python. Le meme menu permet ensuite de mettre a jour,
sauvegarder, restaurer, diagnostiquer ou desinstaller l'application.

## 1. Telecharger le kit

Telechargez l'archive correspondant a votre systeme depuis:

[Derniere version du Client Kit](https://github.com/jimmindev/ai-deep-monitor-client-kit/releases/latest)

- Windows: `ai-deep-monitor-client-kit.zip`
- Linux ou NVIDIA Jetson: `ai-deep-monitor-client-kit.tar.gz`

Les archives s'extraient toujours dans le dossier
`ai-deep-monitor-client-kit`.

## 2. Informations necessaires

L'installation demande:

- un acces Internet;
- un utilisateur GitHub;
- un token GitHub autorise a lire les packages prives `ghcr.io`;
- des droits administrateur sous Windows, ou `sudo` sous Linux.

Docker est verifie automatiquement. S'il est absent, le kit propose ou lance
son installation:

- Docker Desktop avec `winget` sous Windows;
- Docker Engine et Compose v2 sous Linux.

## 3. Installation Windows

1. Extrayez `ai-deep-monitor-client-kit.zip`.
2. Ouvrez PowerShell dans le dossier extrait.
3. Executez uniquement:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\ai-deep-monitor.ps1
```

Choisissez ensuite **1. Installer ou reparer**.

Le dossier d'installation par defaut est `C:\ai-deep-monitor`. Pour utiliser
un autre disque:

```powershell
.\ai-deep-monitor.ps1 -InstallDir "D:\AI-Deep-Monitor"
```

Docker Desktop doit fonctionner en mode **Linux containers**. Le kit detecte
et bloque le mode Windows containers, incompatible avec les images de
l'application.

## 4. Installation Linux ou NVIDIA Jetson

Dans un terminal:

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

Choisissez ensuite **1. Installer ou reparer**.

Le dossier d'installation par defaut est `~/ai-deep-monitor`. Pour utiliser
`/opt`:

```bash
sudo mkdir -p /opt/ai-deep-monitor
sudo chown "$USER":"$USER" /opt/ai-deep-monitor
./ai-deep-monitor.sh --install-dir /opt/ai-deep-monitor
```

Le kit selectionne automatiquement `linux/amd64` sur PC x64 et
`linux/arm64` sur NVIDIA Jetson.

## 5. Ports automatiques

Avant chaque installation ou reparation, le kit controle les ports:

- interface web: `80`, puis `8080`, puis le prochain port libre;
- API: `8000`, puis `8001`, puis le prochain port libre.

Un port deja utilise par cette installation est conserve. Un port appartenant
a un autre service est remplace automatiquement. Les ports retenus sont
enregistres dans `C:\ai-deep-monitor\.env` sous Windows ou dans
`~/ai-deep-monitor/.env` sous Linux.

L'adresse finale est affichee a la fin de l'installation.

## 6. Menu de maintenance

Relancez le meme outil a tout moment.

Windows:

```powershell
C:\ai-deep-monitor\ai-deep-monitor.ps1
```

Linux:

```bash
~/ai-deep-monitor/ai-deep-monitor.sh
```

Le menu permet de:

1. installer ou reparer;
2. verifier et installer une mise a jour;
3. afficher l'etat des services;
4. consulter les journaux;
5. creer une sauvegarde;
6. restaurer une sauvegarde;
7. arreter l'application;
8. demarrer l'application;
9. desinstaller les conteneurs en conservant les donnees;
10. tout supprimer.

## 7. Sauvegarde et restauration

Les sauvegardes contiennent la base MySQL, les donnees API, les MIB importees
et les donnees applicatives. Elles sont creees hors du dossier d'installation.

Utilisez les choix **5** et **6** du menu. Ne supprimez jamais le fichier
`.env` ou les volumes Docker sans sauvegarde.

## 8. Desinstallation

### Desinstallation partielle

Le choix **9** retire les conteneurs et le reseau, mais conserve:

- les volumes MySQL et applicatifs;
- les images Docker;
- la configuration `.env`;
- les sauvegardes.

### Desinstallation complete

Le choix **10. TOUT SUPPRIMER**:

1. demande une confirmation explicite;
2. cree une sauvegarde externe;
3. supprime les conteneurs;
4. supprime MySQL et tous les volumes applicatifs;
5. supprime les images Docker du stack;
6. supprime le dossier d'installation.

Cette operation est irreversible en dehors de la sauvegarde creee juste avant.

## 9. Diagnostic

Si l'API ne demarre pas, l'installateur affiche automatiquement l'etat et les
derniers journaux de MySQL, Ollama, de la sandbox et de l'API.

Vous pouvez aussi choisir **3. Afficher l'etat** ou **4. Afficher les
journaux** dans le menu.

Une erreur `401` sur `/api/auth/refresh` avant connexion est normale lorsqu'il
n'existe pas encore de session. Une erreur `500` sur `/api/auth/login` ne
l'est pas et doit etre diagnostiquee avec les journaux de l'API.

## 10. Securite

- Les sources de l'application ne sont pas presentes dans le kit.
- Les images applicatives restent dans un registre prive.
- Les secrets et mots de passe sont generes sur la machine du client.
- Une installation existante conserve ses comptes et ses volumes.
- Si des volumes SQL existent mais que `.env` a disparu, l'installation
  s'arrete pour eviter de rendre la base inaccessible.

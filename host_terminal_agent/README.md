# Agent terminal hôte

Cet agent permet au terminal d'administration AI-Deep Monitor d'exécuter uniquement
des diagnostics approuvés sur la machine qui héberge Docker, sans exposer de port
réseau ni transmettre de mot de passe système.

Le terminal fonctionne avec une liste blanche stricte appliquée deux fois : dans
l'API et dans l'agent. Les commandes de fichiers, comptes, mots de passe, scripts,
téléchargements, élévation et accès interne aux conteneurs sont refusées.

## Windows

Installation automatique pour l'utilisateur Windows courant :

```powershell
powershell -ExecutionPolicy Bypass -File .\host_terminal_agent\install_windows_task.ps1
```

Avec une console administrateur, une tâche lancée au démarrage de la VM avec
redémarrage automatique est créée. Sans élévation, l'installateur utilise le dossier
de démarrage de l'utilisateur.
Dans les deux cas, l'agent s'exécute avec des droits limités et le mot de passe Windows
n'est ni demandé ni stocké.

Lancement manuel depuis la racine du projet :

```powershell
python .\host_terminal_agent\agent.py
```

Ne lancez pas l'agent en tant qu'administrateur. Il n'a besoin d'aucun privilège
d'élévation pour les diagnostics autorisés.

Pour retirer le démarrage automatique :

```powershell
powershell -ExecutionPolicy Bypass -File .\host_terminal_agent\uninstall_windows_task.ps1
```

## Linux et NVIDIA Jetson

L'installateur détecte automatiquement un Jetson (fichier L4T ou modèle NVIDIA),
installe le même agent protégé et ajoute deux diagnostics virtuels supplémentaires :
`jetson-info` et `jetson-stats`. Ces diagnostics affichent uniquement le modèle, la
version L4T, le noyau, la charge et les températures exposées par `tegrastats`.

Depuis la racine du projet :

```bash
sudo bash ./host_terminal_agent/install_linux_service.sh
```

L'agent est installé comme service systemd avec redémarrage automatique. Il tourne
avec l'utilisateur ayant lancé `sudo`, jamais avec `root`. Pour choisir explicitement
un autre compte non-root :

```bash
sudo bash ./host_terminal_agent/install_linux_service.sh mon_utilisateur
```

Le programme et sa politique sont copiés dans
`/opt/ai-deep-monitor-host-terminal/`, détenus par `root` et en lecture seule pour
l'agent. Le service n'a aucune capacité Linux, ne peut pas élever ses privilèges et
ne peut écrire que dans son état et la file signée `host_terminal_jobs/`.

État et journaux :

```bash
systemctl status ai-deep-monitor-host-terminal.service
journalctl -u ai-deep-monitor-host-terminal.service
```

Pour désinstaller le service sans supprimer la file ni sa clé :

```bash
sudo bash ./host_terminal_agent/uninstall_linux_service.sh
```

Le GID de partage avec le conteneur API vaut `10003` par défaut. Si ce GID est déjà
réservé sur l'hôte, choisissez-en un autre dans `.env` et lors de l'installation :

```bash
HOST_TERMINAL_QUEUE_GID=12003 sudo -E bash ./host_terminal_agent/install_linux_service.sh
```

Après une mise à jour de l'agent ou de la politique, relancez l'installateur : les
fichiers protégés sont remplacés puis le service est redémarré.

## Fonctionnement commun

La communication passe uniquement par `host_terminal_jobs/`. Une clé aléatoire est
créée localement au premier démarrage afin de signer les travaux et leurs réponses.
Ce dossier est ignoré par Git. L'agent utilise un répertoire de travail temporaire,
un environnement minimal et PowerShell sans profil. Sous Windows, `cmd.exe` n'est
pas proposé afin de réduire les possibilités de contournement.

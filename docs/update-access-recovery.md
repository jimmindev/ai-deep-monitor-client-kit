# Réparer la vérification des mises à jour sur une ancienne installation

Un jeton GitHub expiré peut bloquer la détection de version avant le téléchargement
du patch. Installer une nouvelle API n’est donc pas un préalable à sa réparation.
Le message générique `HTTPError` des anciennes versions peut correspondre à ce cas.

Téléchargez et extrayez le dernier Client Kit public depuis sa release `latest`,
puis comparez le SHA256 de l’archive au fichier de sommes publié. Le téléchargement
du kit public ne nécessite pas le jeton GHCR des images privées.

Régénérez le jeton GitHub classic du compte autorisé à lire les deux images avec
`read:packages` uniquement. Conservez le jeton dans un emplacement privé ; il ne
doit pas figurer dans le dépôt, les archives publiques, une commande ou un message.
Lors d’une rotation, chaque installation qui utilisait l’ancien jeton doit recevoir
le nouveau : une release applicative ne peut pas remplacer automatiquement un secret
déjà enregistré sur les autres machines.

Depuis le dossier du kit extrait, sur le client Linux :

```bash
python3 scripts/repair_update_access.py --install-dir "$HOME/ai-deep-monitor"
```

Le jeton est saisi sans être affiché. `--username` permet de préciser le compte si
l’ancien `.env` ne contient pas le bon utilisateur. `--check-only` vérifie les accès
sans modifier l’installation. Python 3, Docker Compose v2 et l’accès au moteur Docker
sont nécessaires ; l’outil ne dépend pas de la version de l’API ni de celle de l’agent.

L’outil valide le jeton et la lecture des deux images avant toute modification,
remplace uniquement `UPDATE_CHECK_USER` et `UPDATE_CHECK_TOKEN`, puis recrée seulement
l’API avec **l’image déjà installée**, sans pull, migration de version ni démarrage
des autres services. Les fichiers Compose et le nom du projet existant sont repris.
Les volumes et les paramètres applicatifs restent conservés. Si l’API ne redevient
pas saine, la configuration précédente est restaurée et son redémarrage est tenté.

Relancez ensuite **Vérifier à nouveau** dans l’application. Si cette action n’existe
pas sur une version très ancienne, utilisez **Mettre à jour** dans le dernier kit
extrait. La mise à jour garde sa sauvegarde et sa vérification Cosign obligatoires.
Ce mécanisme ne dispense pas de vérifier les agents, migrations et signatures lors
du saut de version. Il ne fournit aucun jeton dans les téléchargements publics.

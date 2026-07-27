# AI Deep Monitor Client Kit v0.1.12

Cette version corrige l'arret de l'installation sur NVIDIA Jetson au niveau du
service temporaire `ollama-models`.

## Probleme corrige

Docker Compose interpretait la boucle shell d'installation des modeles comme
plusieurs arguments. Le conteneur executait alors une commande `for` incomplete
et quittait avec le code 2. L'API et le frontend restaient crees mais ne
demarraient pas.

## Correctifs

- la commande d'initialisation est transmise comme un script shell unique ;
- les modeles `llama3.2:1b` et `llama3.2:3b` restent choisis selon les
  ressources detectees par le Client Kit ;
- un modele deja installe n'est pas telecharge de nouveau ;
- un meme modele configure comme principal et secours n'est traite qu'une fois ;
- chaque telechargement peut etre retente trois fois ;
- les journaux utiles sont affiches automatiquement en cas d'echec.

## Donnees preservees

La mise a jour ne recree ni ne supprime les volumes MySQL, les comptes, les
conversations, les configurations, les sauvegardes ou les modeles deja
installes.

## Mise a jour d'une installation bloquee

Depuis le nouveau dossier du Client Kit :

```bash
chmod +x ./*.sh scripts/linux/*.sh
./ai-deep-monitor.sh update
```

L'application reste en `v0.1.5`. Seul le Client Kit passe en `v0.1.12`.

# Evolutions du Client Kit

Le Client Kit suit un canal permanent `latest` et ne possede plus de numero de
version independant. Les archives GitHub gardent toujours le meme nom et sont
remplacees automatiquement apres validation d'une modification sur `main`.

La version d'AI Deep Monitor reste versionnee normalement. L'installateur
detecte la derniere version applicative stable et conserve les donnees, volumes
et reglages lors d'une reparation ou d'une mise a jour.

Le kit prend en charge Windows, Linux x64 et NVIDIA Jetson ARM64. Il fournit le
menu interactif, les sauvegardes/restaurations et l'agent de terminal hote
restreint sans embarquer les sources privees de l'application.

## Correctifs du canal permanent

- Les nouvelles installations utilisent AI Deep Monitor `v0.1.16` par defaut.
- Le Client Kit conserve son URL permanente et detecte automatiquement les
  mises a jour futures sans changer de nom d'archive.

- Les nouvelles installations et mises a jour utilisent AI Deep Monitor
  `v0.1.15` et embarquent l'agent hote `3.5.0 / politique 2.4`.
- Les regles terminal personnalisees sont prioritaires sur le catalogue integre
  dans les deux sens, tout en conservant les protections absolues.
- Une regle portant uniquement le nom d'une commande couvre ses variantes avec
  arguments; les exceptions exactes et propres a l'OS restent prioritaires.
- Le Plan 2D et le Builder 3D affichent les racks automatiques d'une rangee bord
  a bord, sans modifier les placements manuels.

- Les installations utilisent maintenant AI Deep Monitor `v0.1.14`, qui
  maintient la compatibilite avec l'agent Jetson signe `3.3.0 / politique 2.2`
  pendant sa transition vers l'agent `3.4.0 / politique 2.3`.
- Une mise a jour Docker ne classe donc plus cet agent restreint comme non
  securise et ne rend plus le terminal indisponible.

- Le téléchargement initial d'Ollama ne bloque plus le démarrage de l'API et
  du frontend sur NVIDIA Jetson ou en cas d'indisponibilité temporaire.
- Le premier modèle Ollama fonctionnel est conservé ; le modèle de secours
  n'est tenté qu'après l'échec du modèle principal, avec relance automatique
  limitée et diagnostic explicite.
- Les installations utilisent AI Deep Monitor `v0.1.13` par défaut et
  embarquent l'agent hôte `3.4.0` avec la politique terminal `2.3`.
- Le mot de passe fixe de gestion des règles terminal est ajouté aux nouvelles
  installations et aux mises à jour sans écraser une valeur personnalisée.
- `cd`, le répertoire courant persistant et les règles personnalisées signées
  sont livrés sur Windows, Linux et NVIDIA Jetson.
- Le terminal hote accepte maintenant `ls` sur Windows, Linux et NVIDIA
  Jetson au travers d'une routine interne qui affiche uniquement les noms.
- L'agent `3.3.0` et la politique `2.2` bloquent les options, la recursivite,
  les fichiers caches et les repertoires internes de l'application et Docker.
- Les nouvelles installations utilisent AI Deep Monitor `v0.1.12` par defaut.
- Lorsqu’une mise à jour échoue, l’agent conserve maintenant l’étape exacte,
  la cause, le code de retour et les dernières lignes techniques utiles même
  après une restauration automatique réussie.
- Les sauvegardes lancees avant une mise a jour integree sont maintenant
  stockees dans l'espace prive et autorise de l'agent hote. Cela corrige leur
  echec sous Linux et NVIDIA Jetson sans relacher le confinement systemd.
- Les erreurs de maintenance remontent un diagnostic court et expurge des
  mots de passe, tokens et autres secrets.

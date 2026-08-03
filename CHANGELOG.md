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

- Lorsqu’une mise à jour échoue, l’agent conserve maintenant l’étape exacte,
  la cause, le code de retour et les dernières lignes techniques utiles même
  après une restauration automatique réussie.
- Les sauvegardes lancees avant une mise a jour integree sont maintenant
  stockees dans l'espace prive et autorise de l'agent hote. Cela corrige leur
  echec sous Linux et NVIDIA Jetson sans relacher le confinement systemd.
- Les erreurs de maintenance remontent un diagnostic court et expurge des
  mots de passe, tokens et autres secrets.

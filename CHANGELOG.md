# Historique des versions du Client Kit

## v0.1.5 - 2026-07-24

### Ajoute

- Installation Linux complete pour Debian, Ubuntu, Linux Mint, Fedora, RHEL,
  Rocky Linux, AlmaLinux et CentOS.
- Detection et installation automatique de Docker Engine et Compose v2 depuis
  les depots officiels Docker.
- Detection de Docker Desktop sous Windows et installation automatique via
  `winget` lorsqu'il est absent.
- Scripts Linux de verification de version, mise a jour, sauvegarde,
  restauration et desinstallation.
- Selection automatique des ports disponibles sous Linux.
- Sauvegarde Linux au format `.tar.gz` avec checksum SHA-256.
- Restauration Linux des archives `.tar.gz` et des sauvegardes `.zip` Windows.
- Controle contre la traversee de chemins lors de l'extraction d'une sauvegarde.
- Detection des volumes existants et blocage protecteur lorsqu'un `.env` est
  absent.

### Modifie

- Le kit est versionne independamment de l'application.
- La version applicative par defaut reste `v0.1.4`.
- Les documentations Windows et Linux sont rassemblees et detaillees.
- Les scripts installes sont synchronises pour les deux systemes.

### Securite

- Les secrets Linux et les sauvegardes sont limites a l'utilisateur courant.
- Docker est installe depuis des depots signes, sans execution de script
  distant via `curl | sh`.
- Le code source applicatif reste absent du kit.

## v0.1.4 - 2026-07-20

- Ajout d'Ollama au stack Docker client.
- Ajout de la verification de version applicative et de la notification dans
  l'interface.
- Stabilisation du proxy API et du parcours d'authentification client.

## v0.1.3 - 2026-07-15

- Ajout des sauvegardes et restaurations MySQL.
- Ajout des desinstallations partielle et complete.
- Conservation des volumes existants et detection des installations precedentes.

## v0.1.2 - 2026-07-13

- Publication des images privees API et frontend.
- Premier compose client sans code source.

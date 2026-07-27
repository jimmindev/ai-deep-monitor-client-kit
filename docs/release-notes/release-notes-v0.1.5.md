# AI Deep Monitor Client Kit v0.1.5

Cette version rend le kit client exploitable sous Linux et simplifie
l'installation Docker sur tous les postes pris en charge.

## Points principaux

- Installation Linux pour Ubuntu, Debian, Linux Mint, Fedora, RHEL, Rocky,
  AlmaLinux et CentOS.
- Installation automatique de Docker Engine et Compose v2 depuis le depot
  officiel Docker lorsque Docker est absent.
- Installation automatique de Docker Desktop via `winget` sous Windows.
- Scripts Linux complets: installation, verification, mise a jour, sauvegarde,
  restauration et desinstallation.
- Ports frontend et API choisis automatiquement lorsqu'ils sont occupes.
- Reprise sure des installations et volumes Docker existants.
- Sauvegarde MySQL et donnees API avec checksum SHA-256.
- Restauration compatible avec les archives Linux et Windows.
- Documentation client revue pour Windows et Linux.

## Versions

- Client Kit: `v0.1.5`
- Application installee par defaut: `v0.1.4`

La version du kit est volontairement independante de celle des images
applicatives. Cette release ne demande donc pas une image applicative `v0.1.5`.

## Installation

Cette page conserve l'historique fonctionnel de la version `v0.1.5`. Ses
anciens points d'entree d'installation ont ete retires du kit courant.
Utilisez le [guide d'installation actuel](../installation.md).

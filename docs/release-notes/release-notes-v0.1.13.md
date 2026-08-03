# AI Deep Monitor Client Kit v0.1.13

Date de publication : 3 aout 2026

Cette version livre AI Deep Monitor `v0.1.7` et complete son installation sur
Windows, Linux x64 et NVIDIA Jetson ARM64.

## Application v0.1.7

- decouverte SNMP avec inventaire complet, recherche et pagination des OID ;
- ajout direct d'un equipement detecte et d'un OID au catalogue ;
- gestion des profils, familles de materiel et packs MIB ;
- collecteur de telemetrie physique partage par le dashboard, le plan 2D et le
  Builder 3D ;
- terminal de diagnostic de la machine hote pour Windows, Linux et Jetson.

## Installation du terminal hote

Le kit contient uniquement l'agent restreint et sa politique de securite, pas
les sources de l'application. L'installation ou la mise a jour :

1. copie l'agent dans le dossier client ;
2. cree la file locale signee partagee avec l'API ;
3. installe une tache Windows a droits limites ou un service systemd non-root ;
4. recharge automatiquement la politique lors d'une mise a jour.

Python 3 est installe automatiquement lorsqu'il est absent. Une erreur
d'installation de l'agent n'empeche pas les autres fonctions de demarrer et le
diagnostic indique la commande manuelle a utiliser.

## Securite

- aucun mot de passe n'est transmis au shell ni utilise comme mot de passe
  `sudo` ;
- les commandes sont validees par l'API puis par l'agent ;
- les acces aux fichiers, comptes, mots de passe, scripts et contenus internes
  des conteneurs restent interdits ;
- la file locale HMAC ne publie aucun port reseau supplementaire ;
- la session expire automatiquement.

## Mise a jour

L'outil cree une sauvegarde avant un changement de version applicative,
conserve le fichier `.env`, les ports et tous les volumes existants, puis
installe les images `v0.1.7` pour `linux/amd64` ou `linux/arm64`.

Lancer :

```bash
./ai-deep-monitor.sh update
```

ou sous Windows :

```powershell
.\ai-deep-monitor.ps1 -Command update
```

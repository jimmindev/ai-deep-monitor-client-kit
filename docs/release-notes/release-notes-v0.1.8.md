# AI Deep Monitor Client Kit v0.1.8

Cette version améliore l'utilisation quotidienne du kit sans modifier la
version de l'application, qui reste en `v0.1.5`.

## Menu persistant

- Le lanceur revient automatiquement au menu après chaque action.
- Une erreur dans une opération ne ferme plus le programme principal.
- Un message invite à continuer avant de réafficher le menu.
- Le choix `0` ou la touche `Q` restent les seules sorties volontaires.

## Navigation interactive

- Linux et Jetson prennent en charge les flèches haut/bas et la touche Entrée.
- Windows bénéficie du même mode interactif dans un terminal compatible.
- Un menu numérique reste disponible lorsque le terminal ne gère pas les
  touches interactives.

## Maintenance

- Gestion centralisée des sauvegardes depuis le lanceur.
- Documentation simplifiée et retrait des anciennes procédures.
- Test de non-régression garantissant que le menu survit aux erreurs d'action.

## Compatibilité

- Linux `amd64`
- Linux et Jetson `arm64`
- Windows avec Docker Desktop

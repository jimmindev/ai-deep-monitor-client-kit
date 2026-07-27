# AI Deep Monitor Client Kit v0.1.9

Date: 27 juillet 2026

## Version livree

- Client Kit: `v0.1.9`
- Application installee: `v0.1.5`

Cette version ameliore uniquement l'outil de maintenance client. Elle ne
modifie ni l'application, ni son API, ni la structure de la base MySQL.

## Suppression ciblee des sauvegardes

Le gestionnaire permet maintenant de supprimer exactement les archives
choisies:

- navigation avec les fleches;
- coche ou decoche avec `Espace`;
- selection multiple;
- validation avec `Entree`;
- annulation avec `Q`;
- confirmation avant suppression.

Dans un terminal ne prenant pas en charge le selecteur interactif, la selection
se fait par numeros et plages, par exemple `1,3,5-7`.

## Securite

- Les archives sont resolues par nom exact.
- Les sauvegardes non selectionnees sont conservees.
- La suppression de toutes les archives reste une action distincte.
- Aucun nettoyage silencieux n'est effectue pendant une installation, une mise
  a jour ou une desinstallation.

## Validation

- Test cible Linux avec archives aux noms proches.
- Test Windows de retention puis suppression selective.
- Analyse syntaxique Shell et PowerShell.

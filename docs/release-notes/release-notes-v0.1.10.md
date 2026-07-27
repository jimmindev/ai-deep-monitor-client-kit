# AI Deep Monitor Client Kit v0.1.10

Date: 27 juillet 2026

## Versions

- Client Kit: `v0.1.10`
- Application installee: `v0.1.5`

## Navigation uniforme

Tous les menus Linux, NVIDIA Jetson et Windows utilisent maintenant la meme
interaction:

1. saisir le numero de l'action;
2. valider avec `Entree`;
3. saisir `0` pour revenir ou quitter.

Le menu principal reste ouvert apres chaque action, y compris apres une erreur.

## Gestion des sauvegardes

Les sauvegardes sont affichees avec un numero, leur date, leur taille et leur
nom. Une suppression ciblee accepte:

- un numero: `2`;
- plusieurs numeros: `1,3,5`;
- une plage: `2-5`;
- une combinaison: `1,3,5-7`.

Une saisie vide annule l'operation et une confirmation reste obligatoire avant
toute suppression.

## Compatibilite

- Linux x86_64;
- NVIDIA Jetson ARM64;
- Windows avec Docker Desktop.

Cette version ne change pas les volumes SQL, les donnees applicatives ni la
version de l'application.

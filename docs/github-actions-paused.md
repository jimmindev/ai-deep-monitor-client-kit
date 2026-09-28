# GitHub Actions suspendues

Depuis le 29 septembre 2026, GitHub Actions est désactivé au niveau des dépôts `jimmindev/ai-deep-monitor` et `jimmindev/ai-deep-monitor-client-kit` (`enabled=false`). Les workflows sont conservés sans modification pour permettre leur réactivation.

**Ne pas réactiver GitHub Actions sans une demande explicite de l’utilisateur.** Une demande de patch, publication ou déploiement ne constitue pas une demande de réactivation.

## Publier pendant la suspension

Effectuer les tests localement avant de fusionner les changements. Promouvoir le correctif de develop vers preprod puis main avec des PR. Préprod représente ici une branche GitHub, sans instance à déployer.

Pour le kit client, exécuter les tests Python et les contrôles Linux/Windows pertinents, puis `bash scripts/package-release.sh artifacts` dans le dépôt client. Publier ZIP, TAR.GZ et SHA256 avec `gh release upload latest ... --clobber`, puis faire pointer le tag latest sur le commit publié. Les liens de téléchargement permanents restent identiques. Ne jamais inclure de fichier .env ni d’identifiant dans les archives.

Si le code API/frontend change, construire et publier depuis un poste autorisé avec Docker Buildx pour linux/amd64 et linux/arm64. Ne pas utiliser le cache GitHub Actions ni dispatch de workflow. Valider les images avant de promouvoir leurs digests vers develop, preprod, main/latest et un nouveau tag de version. Conserver les exigences de signature du client ; ne pas les désactiver pour contourner la suspension. Un correctif uniquement dans l’agent hôte ne nécessite pas de reconstruire les images applicatives.

## Réactiver uniquement sur demande explicite

1. Vérifier les workflows `.github/workflows/` des deux dépôts, leurs permissions et secrets/variables. Consulter la configuration actuelle avant tout changement.
2. Après autorisation explicite, exécuter :

```powershell
gh api -X PUT repos/jimmindev/ai-deep-monitor/actions/permissions -F enabled=true
gh api -X PUT repos/jimmindev/ai-deep-monitor-client-kit/actions/permissions -F enabled=true
```

3. Vérifier avec `gh api repos/jimmindev/ai-deep-monitor/actions/permissions` et l’équivalent pour le kit. Si un workflow a été désactivé individuellement entre-temps, le réactiver explicitement avec `gh workflow enable <fichier> --repo <dépôt>`.
4. Lancer d’abord les validations manuelles nécessaires. Ne lancer les workflows de publication qu’après validation : ils peuvent remplacer les tags d’images et les archives de la release latest.
5. Documenter la date de réactivation et l’autorisation dans ce fichier.

## Correctif synchronisé

L’agent de stockage autorise l’administrateur à retirer une connexion utilisée pour la maintenance. Les archives distantes restent intactes, les configurations liées sont désactivées et les opérations en cours restent protégées. Le kit client officiel publie l’agent 3.6.8. L’application reste v0.1.48 : ses images ne contiennent pas l’agent installé comme service sur l’hôte.

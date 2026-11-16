# Publication manuelle du Client Kit

GitHub Actions reste désactivé jusqu’à une demande explicite de réactivation.

Utiliser `scripts/package-release.sh` pour préparer les archives. Les scripts Linux (`.sh`, `.py`) doivent avoir des fins de ligne LF ; le script de packaging les normalise avant archivage.

Le fichier `ai-deep-monitor-client-kit-SHA256.txt` doit également être écrit en LF, sans BOM, avec le nom exact de chaque archive. Recalculer les sommes après toute modification des archives. Publier ensemble le ZIP, le TAR.GZ et le fichier SHA256 dans la release `latest`.

Avant publication, vérifier les scripts Linux extraits et les SHA256. Après remplacement d’un asset GitHub, vérifier son téléchargement public : un cache peut encore servir l’ancien fichier quelques instants.

## MySQL pour les installations v0.1.159

Les nouvelles installations fixent MYSQL_IMAGE sur MySQL 8.4.13. Les installations existantes sans cette variable conservent MySQL 8.0.46 : le patch applicatif ne migre pas leur volume. Une migration 8.0 vers 8.4 exige une sauvegarde vérifiée, un essai de restauration et une bascule planifiée. Ne pas réouvrir en 8.0 un volume déjà ouvert par 8.4.

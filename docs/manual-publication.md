# Publication manuelle du Client Kit

GitHub Actions reste désactivé jusqu’à une demande explicite de réactivation.

Utiliser `scripts/package-release.sh` pour préparer les archives. Les scripts Linux (`.sh`, `.py`) doivent avoir des fins de ligne LF ; le script de packaging les normalise avant archivage.

Le fichier `ai-deep-monitor-client-kit-SHA256.txt` doit également être écrit en LF, sans BOM, avec le nom exact de chaque archive. Recalculer les sommes après toute modification des archives. Publier ensemble le ZIP, le TAR.GZ et le fichier SHA256 dans la release `latest`.

Avant publication, vérifier les scripts Linux extraits et les SHA256. Après remplacement d’un asset GitHub, vérifier son téléchargement public : un cache peut encore servir l’ancien fichier quelques instants.

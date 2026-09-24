# Dossiers de sauvegarde sur le serveur Linux

Dans Configuration → État de l’application → Stockage, utilisez **Ajouter un emplacement sur le serveur**.

1. Parcourez les dossiers du serveur ou saisissez le chemin d’un dossier parent existant, par exemple `/mnt` ou `/home/votre-utilisateur`, puis cliquez sur **Ouvrir**.
2. Saisissez un nouveau nom, par exemple `mes-sauvegardes`.
3. Cliquez sur **Créer et partager ce dossier**. Le serveur crée `/mnt/mes-sauvegardes` dans cet exemple ; il ne s’agit pas d’un sous-dossier de `/backups`.
4. Après vérification de l’écriture par l’API et le planificateur, choisissez le dossier puis **Créer une sauvegarde dans ce dossier**.

L’opération est réservée aux administrateurs. Elle crée uniquement un nouveau dossier : elle ne change pas les droits d’un dossier existant. Les répertoires système, les liens symboliques, les dossiers cachés et le dossier d’installation sont exclus. Le disque doit proposer un UUID de système de fichiers pour retrouver le bon support après redémarrage.

## Installation et persistance

Cette fonction nécessite la nouvelle version de l’API, du frontend et de l’agent de stockage du kit client Linux. Le kit doit inclure `host_storage_agent/locations.py`. Depuis l’installation du client, l’administrateur installe l’agent avec :

```sh
sudo bash host_storage_agent/install_linux_service.sh
```

L’installation prépare les montages partagés et recrée l’API et le planificateur si nécessaire. L’agent terminal doit également être installé : sa clé et son répertoire `host_terminal_jobs` servent à authentifier les demandes. Il n’y a pas de commande shell libre dans cette fonction.

Les associations sont conservées dans `/var/lib/ai-deep-monitor-storage/locations.json`, accessible uniquement à root. Chaque dossier est partagé sous `/mnt/ai-deep-monitor-locations/<identifiant>`, visible dans les conteneurs sous `/host/mnt/ai-deep-monitor-locations/<identifiant>`. L’interface affiche son chemin réel. Le service recrée ces montages après redémarrage, en vérifiant que le système de fichiers d’origine est disponible ; il ne crée pas un dossier de remplacement si le disque est absent.

Si la vérification des conteneurs échoue après création, le dossier et son association sont conservés. Corrigez l’accès de l’API et du planificateur, puis réessayez avec le même dossier parent et le même nom. Un agent absent ou trop ancien produit un message explicite, sans simuler une création dans le conteneur. La création sur un hôte Windows n’est pas prise en charge par cet agent Linux.

## Vérifications

Les tests couvrent les droits administrateur, les signatures, les demandes expirées/rejouées, les chemins protégés, les dossiers existants, la restauration des associations et le contrôle des deux services. Un test Linux isolé avec un vrai bind mount vérifie aussi l’écriture et le remontage. Les tests navigateur couvrent le parcours sur ordinateur et mobile.

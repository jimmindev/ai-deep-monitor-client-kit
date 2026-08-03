# AI Deep Monitor Client Kit v0.1.14

Cette version installe AI Deep Monitor `v0.1.8` et active la mise a jour
securisee directement depuis le badge de version de l'application.

## Parcours administrateur

1. Cliquer sur la version dans la barre de navigation.
2. Consulter la version cible et les informations de maintenance.
3. Confirmer le mot de passe administrateur AI Deep Monitor.
4. Laisser l'agent creer la sauvegarde, telecharger les images puis redemarrer
   les services.
5. Recharger l'application lorsque le controle de sante est termine.

Le mot de passe n'est jamais transmis a l'agent ou a Docker. La file de
maintenance est signee localement et n'accepte qu'une version stable publiee
par AI Deep Monitor. Toute retrogradation est refusee.

En cas d'echec, le fichier d'environnement precedent et les anciennes images
sont reactives automatiquement. La sauvegarde complete reste disponible dans
le dossier de sauvegardes du client.

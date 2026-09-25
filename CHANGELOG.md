# Evolutions du Client Kit

## Application v0.1.42

- Les nouvelles installations ciblent AI Deep Monitor `v0.1.42` par défaut.
- L’agent de stockage Linux refuse de supprimer un emplacement contenant une archive non répertoriée ou un fichier étranger, afin de préserver les données du support.
- Les mises à jour intégrées conservent les montages Linux des clés USB et dossiers hôtes, y compris pendant un retour à la version précédente.
- Les installations existantes peuvent se mettre à jour sans effacer leurs volumes, comptes ou réglages.

## Application v0.1.37

- Version applicative par défaut : v0.1.37.
- Réparation ciblée des droits de sauvegarde et rechargement du proxy après préparation du stockage Linux.
- Inventaire des supports avec liens parent/enfant et type USB hérité par les volumes.


Le Client Kit suit un canal permanent `latest` et ne possede plus de numero de
version independant. Les archives GitHub gardent toujours le meme nom et sont
remplacees automatiquement apres validation d'une modification sur `main`.

La version d'AI Deep Monitor reste versionnee normalement. L'installateur
detecte la derniere version applicative stable et conserve les donnees, volumes
et reglages lors d'une reparation ou d'une mise a jour.

Le kit prend en charge Windows, Linux x64 et NVIDIA Jetson ARM64. Il fournit le
menu interactif, les sauvegardes/restaurations et l'agent de terminal hote
restreint sans embarquer les sources privees de l'application.

## Application v0.1.36

- Les nouvelles installations utilisent AI Deep Monitor `v0.1.36` par défaut.
- Le service Linux autorise la création de dossiers à la racine des disques de
  données qu’il monte automatiquement, sans toucher aux fichiers existants ni
  au disque système.

## Application v0.1.35

- Les nouvelles installations utilisent AI Deep Monitor `v0.1.35` par défaut.
- Le dossier de sauvegarde Linux géré par le kit reçoit les droits d’écriture
  requis par les conteneurs API et planificateur. Un chemin personnalisé n’est
  pas modifié.
- La fenêtre de sauvegarde conserve sa liste pendant l’actualisation des
  volumes, sans saut répété de l’interface.

## Application v0.1.34

- Les nouvelles installations utilisent AI Deep Monitor `v0.1.34` par défaut.
- Le kit Linux installe le service horaire hôte limité, utilisé par l'interface
  Docker pour appliquer le fuseau et le serveur NTP.
- Le kit Linux active la découverte et le montage automatiques des disques de
  données et expose leurs dossiers aux services de sauvegarde.
- Les installations existantes conservent leurs identifiants et peuvent être
  mises à jour via le menu du Client Kit.

## Application v0.1.31

- Les nouvelles installations utilisent AI Deep Monitor `v0.1.31` par défaut.
- L'agent hôte 3.6.3 remonte le modèle matériel et le pilote des cartes réseau
  Linux et Raspberry Pi à partir des données udev et device tree lorsqu'elles
  sont disponibles. La lecture ne modifie pas la configuration réseau.
- Pour voir ces informations sur une installation existante, actualiser le
  Client Kit afin de remplacer l'agent local, puis mettre à jour l'application.

## Application v0.1.30

- Les nouvelles installations Windows, Linux, Jetson et Raspberry Pi utilisent
  AI Deep Monitor `v0.1.30` par défaut.
- L'API détecte les interfaces réseau Linux même lorsque l'agent hôte installé
  est encore en version 3.6.0. Une mise à jour du Client Kit installe toujours
  l'agent 3.6.2 pour les diagnostics complets.

## Application v0.1.29

- Les nouvelles installations Windows, Linux, Jetson et Raspberry Pi utilisent
  AI Deep Monitor `v0.1.29` par défaut.
- Cette version corrige le rendu des libellés du Builder 3D sur Chromium ARM,
  afin que la pose et la sélection des racks restent disponibles.
## Application v0.1.28

- Les nouvelles installations Windows, Linux et Jetson utilisent AI Deep Monitor
  `v0.1.28` par défaut.
- Le kit conserve les contrôles de mise à jour, de migration et de restauration
  avant le redémarrage des services.
## Application v0.1.26

- Reprise des migrations MySQL interrompues, sans doublon d’index.
- Migration préalable au redémarrage dans les outils Windows et Linux.
- Agent 3.6.2 : délai de migration distinct de six heures, conteneur dédié et
  nettoyage après dépassement ; intervention demandée si le nettoyage échoue.
- Tests d’exécution des scripts sur succès et erreur de migration, obligatoires
  avant publication des archives.

## Application v0.1.25

- Images 0.1.25 et workers de sauvegarde, découverte et notification.
- Licences cumulées, secrets de sauvegarde persistants et inventaire des interfaces hôte.
- Profil DHCP Linux facultatif, sans activation automatique.

## Correctifs du canal permanent

- L’agent 3.6.1 prépare les migrations de base de données avant de redémarrer
  l’API, pour éviter qu’un contrôle de santé interrompe la création d’index
  sur les grandes bases. Une erreur de migration bloque le déploiement.

- L'installation Windows/Linux cible maintenant AI Deep Monitor `v0.1.24`.
  Cette publication conserve les données et le profil matériel pendant la
  mise à jour, puis vérifie les services et la version exposée par l'API.

- L'installation Windows/Linux cible maintenant AI Deep Monitor `v0.1.23`.
  Les mises a jour conservent les donnees et le profil CPU/GPU detecte, tout
  en actualisant les fichiers du Client Kit et l'agent terminal.

- Le premier demarrage sur une base MySQL vierge attend maintenant le serveur
  TCP definitif; les migrations API retentent aussi les coupures transitoires
  au lieu de rendre le service unhealthy.
- Sur NVIDIA Jetson, la detection ne telecharge plus l'image CUDA generique
  avant la construction locale: le kit utilise directement CUDA/JetPack et le
  compute capability detectes sur la machine.
- La construction ARM64 de llama.cpp autorise les bibliotheques CUDA fournies
  au runtime par JetPack et limite par defaut la compilation a quatre taches,
  ce qui corrige l'echec final d'edition de liens observe sur Jetson Orin.
- Le nombre de taches peut etre ajuste avec `LLAMA_CPP_CUDA_BUILD_JOBS`; les
  images personnalisees et les images locales deja construites restent testees
  et reutilisees.

- La mise a jour integree actualise maintenant le Client Kit `latest` avant
  l'application: installateurs Windows/Linux, Compose, documentation et agent
  terminal sont telecharges, controles par SHA256 puis synchronises.
- L'agent hote `3.6.0` applique la meme sequence lors d'une mise a jour lancee
  depuis l'interface web et remonte une erreur dediee si le Client Kit ne peut
  pas etre valide.

- L'installation reelle impose maintenant l'authentification GHCR, valide le
  token sur les deux images privees et protege les secrets avec des ACL Windows
  restrictives.
- Le runtime llama.cpp est maintenant detecte par machine: NVIDIA CUDA sur
  Windows/Linux, runtime JetPack sur Jetson, ou CPU sans dependance GPU.
- Une image CUDA locale est construite automatiquement lorsque l'image
  officielle ne correspond pas a la version CUDA ou au compute capability.
- Le profil valide est conserve dans `.env` pendant les mises a jour; une
  redetection explicite reste disponible pour un changement de materiel.

- Les nouvelles installations utilisent AI Deep Monitor `v0.1.22` par defaut.
- Le moteur conversationnel Ollama est remplace par llama.cpp CUDA, avec
  dechargement prioritaire de toutes les couches compatibles sur le GPU.
- L'installation et la mise a jour verifient la disponibilite du GPU NVIDIA et
  du runtime Docker avant de telecharger ou redemarrer les images.
- Une ancienne configuration Ollama est migree automatiquement vers les
  variables llama.cpp sans supprimer les volumes historiques des sauvegardes.

- Les nouvelles installations utilisent AI Deep Monitor `v0.1.21` par defaut.
- Le mode 3D realiste charge correctement les textures GLB avec la politique de
  securite de production.

- Les nouvelles installations utilisent AI Deep Monitor `v0.1.20` par defaut.
- Le kit livre les optimisations de chargement du Dashboard, de SmartState et
  des devices virtuels, ainsi que les historiques cibles pour les courbes.

- Les nouvelles installations utilisent AI Deep Monitor `v0.1.19` par defaut.
- Le kit livre la navigation SmartState complete : familles et compositions
  cliquables, fil d'Ariane et remontee vers chaque niveau du Datacenter Builder.

- Les nouvelles installations utilisent AI Deep Monitor `v0.1.18` par defaut.
- Le kit livre SmartState multi-sources, les cartes Dashboard multi-informations
  et les correctifs de synchronisation et de placement du Builder 2D/3D.

- Les nouvelles installations utilisent AI Deep Monitor `v0.1.17` par defaut.
- Le menu permanent installe SmartState, son integration Dashboard et le
  gabarit 42U normalise sans changer l'URL ni le nom du kit.

- Les nouvelles installations utilisent AI Deep Monitor `v0.1.16` par defaut.
- Le Client Kit conserve son URL permanente et detecte automatiquement les
  mises a jour futures sans changer de nom d'archive.

- Les nouvelles installations et mises a jour utilisent AI Deep Monitor
  `v0.1.15` et embarquent l'agent hote `3.5.0 / politique 2.4`.
- Les regles terminal personnalisees sont prioritaires sur le catalogue integre
  dans les deux sens, tout en conservant les protections absolues.
- Une regle portant uniquement le nom d'une commande couvre ses variantes avec
  arguments; les exceptions exactes et propres a l'OS restent prioritaires.
- Le Plan 2D et le Builder 3D affichent les racks automatiques d'une rangee bord
  a bord, sans modifier les placements manuels.

- Les installations utilisent maintenant AI Deep Monitor `v0.1.14`, qui
  maintient la compatibilite avec l'agent Jetson signe `3.3.0 / politique 2.2`
  pendant sa transition vers l'agent `3.4.0 / politique 2.3`.
- Une mise a jour Docker ne classe donc plus cet agent restreint comme non
  securise et ne rend plus le terminal indisponible.

- Le téléchargement initial d'Ollama ne bloque plus le démarrage de l'API et
  du frontend sur NVIDIA Jetson ou en cas d'indisponibilité temporaire.
- Le premier modèle Ollama fonctionnel est conservé ; le modèle de secours
  n'est tenté qu'après l'échec du modèle principal, avec relance automatique
  limitée et diagnostic explicite.
- Les installations utilisent AI Deep Monitor `v0.1.13` par défaut et
  embarquent l'agent hôte `3.4.0` avec la politique terminal `2.3`.
- Le mot de passe fixe de gestion des règles terminal est ajouté aux nouvelles
  installations et aux mises à jour sans écraser une valeur personnalisée.
- `cd`, le répertoire courant persistant et les règles personnalisées signées
  sont livrés sur Windows, Linux et NVIDIA Jetson.
- Le terminal hote accepte maintenant `ls` sur Windows, Linux et NVIDIA
  Jetson au travers d'une routine interne qui affiche uniquement les noms.
- L'agent `3.3.0` et la politique `2.2` bloquent les options, la recursivite,
  les fichiers caches et les repertoires internes de l'application et Docker.
- Les nouvelles installations utilisent AI Deep Monitor `v0.1.12` par defaut.
- Lorsqu’une mise à jour échoue, l’agent conserve maintenant l’étape exacte,
  la cause, le code de retour et les dernières lignes techniques utiles même
  après une restauration automatique réussie.
- Les sauvegardes lancees avant une mise a jour integree sont maintenant
  stockees dans l'espace prive et autorise de l'agent hote. Cela corrige leur
  echec sous Linux et NVIDIA Jetson sans relacher le confinement systemd.
- Les erreurs de maintenance remontent un diagnostic court et expurge des
  mots de passe, tokens et autres secrets.

Le suivi de migration est rafraîchi toutes les 30 secondes pour éviter une expiration pendant une opération SQL longue.

# Serveur DHCP

Le serveur DHCP est fourni par Kea dans un profil Docker séparé. Il utilise le réseau de l’hôte pour répondre aux diffusions DHCP et ne doit être activé que sur une interface LAN dédiée.

1. Ouvrez **Configuration → Réseau et date / heure → DHCP** et enregistrez l’interface, le sous-réseau, la plage, les DNS et les réservations.
2. Sur Linux ou Jetson, démarrez le profil :

```bash
docker compose -f docker-compose.release.yml -f docker-compose.dhcp.yml --profile dhcp up -d dhcp-server
```

3. La page indique ensuite si le service Kea répond. Les modifications enregistrées sont appliquées immédiatement lorsque le service est en cours, puis conservées dans le volume Docker `dhcp_config`.

Docker Desktop sous Windows ne prend pas en charge la diffusion DHCP sur le LAN : la page permet de préparer la configuration, mais le serveur doit être exécuté sur Linux ou Jetson. Le port UDP 67 doit être libre sur l’hôte et un seul serveur DHCP doit être actif sur le même réseau.

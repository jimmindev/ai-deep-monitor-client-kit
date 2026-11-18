# Accès sous /aideepmonitor/

L’interface publiée accepte un chemin de base local fourni par la balise HTML `<base>`. Les fichiers compilés sont relatifs et le routeur, l’API, la carte des fuseaux et les modèles 3D suivent ce chemin. Aucun JavaScript n’est modifié par le proxy et aucune directive CSP n’est affaiblie.

Le snippet `deploy/nginx/aideepmonitor.conf` remplace uniquement l’ancienne copie statique par le frontend actif sur 127.0.0.1:8082. L’API reste sur 127.0.0.1:18001 et les cookies conservent le chemin `/aideepmonitor/`. Ces ports sont ceux de l’installation diagnostiquée ; les adapter explicitement sur une autre installation.

Le serveur HTTPS existant doit déjà inclure `/etc/nginx/snippets/aideepmonitor.conf`. Après mise à jour des images, exécuter `sudo bash deploy/nginx/install-aideepmonitor.sh` depuis le Client Kit actualisé. L’outil exige le support du chemin dans le frontend, sauvegarde le snippet existant, teste Nginx puis recharge ; en cas d’erreur, l’ancienne configuration est restaurée. Il ne change pas le certificat ni les autres sites et ne supprime pas `/var/www/aideepmonitor`.

Les mises à jour suivantes utilisent directement les nouveaux conteneurs. Aucune copie de fichiers dans `/var/www` n’est nécessaire. L’accès racine reste compatible. Le certificat TLS du domaine reste à utiliser avec son nom DNS valide, sans contourner sa vérification pour une adresse IP.

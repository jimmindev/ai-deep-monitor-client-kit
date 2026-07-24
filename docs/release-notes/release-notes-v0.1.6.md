# AI Deep Monitor Client Kit v0.1.6

Cette version corrige l'installation Linux lorsqu'elle est lancee par un
utilisateur standard, en particulier sur Ubuntu et NVIDIA Jetson.

## Probleme corrige

Le kit `v0.1.5` testait la disponibilite des ports en essayant de les ouvrir.
Un utilisateur non privilegie ne peut pas ouvrir directement les ports
inferieurs a `1024`. Le refus d'acces etait alors interprete comme un port
occupe, jusqu'a produire l'erreur:

```text
[AI Deep Monitor] ERREUR: Aucun port disponible a partir de 80.
```

## Nouveau comportement

- Les ports en ecoute sont detectes sans ouverture de socket privilegiee.
- Le port `80` est conserve automatiquement lorsqu'il est libre.
- Si le port `80` est reellement occupe, le prochain port libre est choisi.
- La detection utilise `ss`, puis les tables TCP du noyau Linux.
- Un mecanisme de repli Python reste disponible sur les environnements
  minimaux.

## Validation

- Installation sans demarrage sous Linux.
- Detection du port `80` avec un utilisateur non privilegie.
- Detection d'un port reellement occupe.
- Selection du prochain port disponible.
- Validation syntaxique Shell et PowerShell.

## Versions

- Client Kit: `v0.1.6`
- Application installee par defaut: `v0.1.4`

Cette mise a jour concerne uniquement les scripts du kit. Elle ne modifie pas
les images applicatives React, Python, MySQL ou Ollama.

## Installation Linux

```bash
curl -fL \
  -o ai-deep-monitor-client-kit-v0.1.6.tar.gz \
  https://github.com/jimmindev/ai-deep-monitor-client-kit/releases/download/v0.1.6/ai-deep-monitor-client-kit-v0.1.6.tar.gz
tar -xzf ai-deep-monitor-client-kit-v0.1.6.tar.gz
cd ai-deep-monitor-client-kit-v0.1.6
chmod +x ./*.sh
./install-client.sh
```

Un token GitHub autorise a lire les images privees GHCR reste necessaire.

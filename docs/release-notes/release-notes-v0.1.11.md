# AI Deep Monitor Client Kit v0.1.11

Cette version corrige le demarrage du Chat Bot sur les Jetson Nano et les
installations ayant conserve une ancienne configuration Ollama.

## Correctifs

- migration automatique de `llama3.1` vers un modele actuellement distribue ;
- utilisation de `llama3.2:1b` sur les machines ARM64 disposant de moins de
  6 Go de RAM ;
- utilisation de `llama3.2:3b` sur les autres machines ;
- installation de `llama3.2:1b` comme modele de secours ;
- nouvelle synchronisation des conteneurs apres une reparation de la
  configuration Ollama.

Les volumes MySQL, les comptes, les conversations et les autres donnees
persistantes ne sont ni recrees ni supprimes pendant cette mise a jour.

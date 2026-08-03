# AI Deep Monitor Client Kit v0.1.15

Cette version corrective livre AI Deep Monitor `v0.1.9` et repare sa
distribution ainsi que l'activation du terminal hote.

## Correctifs importants

- Les archives ZIP et TAR.GZ contiennent de nouveau un seul dossier
  `ai-deep-monitor-client-kit/`.
- `AI-Deep-Monitor.cmd` ouvre directement le menu sous Windows.
- Les menus Windows, Linux et NVIDIA Jetson proposent une action unique pour
  installer, reparer et verifier le terminal hote.
- L'installation Linux/Jetson controle le service systemd et le signal signe.
  Elle affiche automatiquement l'etat et les journaux en cas d'echec.
- L'installation Windows attend egalement un signal valide de l'agent et ne
  masque plus un echec de demarrage.

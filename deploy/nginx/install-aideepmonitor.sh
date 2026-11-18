#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$EUID" == 0 ]] || { echo "Executez ce script avec sudo." >&2; exit 1; }
script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
target=/etc/nginx/snippets/aideepmonitor.conf
source_file="${script_dir}/aideepmonitor.conf"
for command_name in nginx curl systemctl; do command -v "$command_name" >/dev/null || { echo "Commande absente: $command_name" >&2; exit 1; }; done
[[ -f "$source_file" && -f "$target" && ! -L "$target" ]] || { echo "Snippet existant ou modele introuvable. Aucun changement." >&2; exit 1; }
# Never replace a working site before the installed frontend supports a base path.
html="$(curl -fsS --max-time 10 http://127.0.0.1:8082/)"
grep -Fq '<base href="/">' <<< "$html" || { echo "Mettez d abord le frontend a jour: prise en charge du sous-chemin absente." >&2; exit 1; }
nginx -t
backup="$(mktemp "${target}.backup.XXXXXX")"
cp -p -- "$target" "$backup"
temporary="$(mktemp "${target}.new.XXXXXX")"
trap 'rm -f -- "$temporary"' EXIT
cp -- "$source_file" "$temporary"
chmod 644 "$temporary"
mv -- "$temporary" "$target"
if ! nginx -t; then
  cp -p -- "$backup" "$target"
  echo "Configuration refusee. Ancien fichier restaure; aucun rechargement." >&2
  exit 1
fi
if ! systemctl reload nginx; then
  cp -p -- "$backup" "$target"
  nginx -t && systemctl reload nginx
  echo "Rechargement echoue. Ancienne configuration restauree." >&2
  exit 1
fi
echo "Acces /aideepmonitor/ configure vers les conteneurs en cours."
echo "Sauvegarde de la configuration precedente: $backup"

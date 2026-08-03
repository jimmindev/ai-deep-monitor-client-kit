from __future__ import annotations

import re


POLICY_VERSION = "2.1"
MAX_COMMAND_BYTES = 4_000


class TerminalPolicyViolation(ValueError):
    def __init__(self, category: str, message: str):
        super().__init__(message)
        self.category = category


_BLOCKED_SYNTAX = (
    (re.compile(r"[\x00\r\n;]"), "scripts", "Les commandes multiples et les scripts sont interdits."),
    (re.compile(r"&&|\|\|"), "scripts", "Le chaînage de commandes est interdit."),
    (re.compile(r"[<>`]"), "filesystem", "Les redirections et substitutions sont interdites."),
    (re.compile(r"[$'\"{}()\[\]]"), "scripts", "Les variables, expressions et blocs de script sont interdits."),
    (re.compile(r"&"), "scripts", "L'opérateur d'exécution est interdit."),
)

_SAFE_PROPERTIES = {
    "addressfamily",
    "average",
    "caption",
    "count",
    "cpu",
    "csname",
    "destinationprefix",
    "displayname",
    "dnsserver",
    "drive",
    "filesystem",
    "free",
    "freephysicalmemory",
    "handles",
    "healthstatus",
    "id",
    "ifindex",
    "interfacealias",
    "interfaceindex",
    "ipv4address",
    "ipv4defaultgateway",
    "ipv6address",
    "lastbootuptime",
    "linklayerspeed",
    "localaddress",
    "localport",
    "macaddress",
    "machineName".lower(),
    "maximum",
    "minimum",
    "name",
    "nexthop",
    "netprofile",
    "objectid",
    "operationalstatus",
    "osarchitecture",
    "processname",
    "protocol",
    "provider",
    "remoteaddress",
    "remoteport",
    "responding",
    "root",
    "routemetric",
    "size",
    "sizeremaining",
    "starttime",
    "starttype",
    "state",
    "status",
    "sum",
    "totalvisiblememorysize",
    "used",
    "version",
    "workingSet64".lower(),
}

_SAFE_CIM_CLASSES = {
    "win32_computersystem",
    "win32_logicaldisk",
    "win32_networkadapterconfiguration",
    "win32_operatingsystem",
    "win32_physicalmemory",
    "win32_processor",
}

_NO_ARGUMENT_POWERSHELL = {
    "get-date",
    "get-dnsclientserveraddress",
    "get-netadapter",
    "get-netipconfiguration",
    "get-netroute",
    "get-nettcpconnection",
    "get-process",
    "get-service",
    "get-uptime",
    "get-volume",
}

_PIPELINE_COMMANDS = {
    "format-list",
    "format-table",
    "measure-object",
    "select-object",
    "sort-object",
}

_HOST_PATTERN = re.compile(r"^[A-Za-z0-9](?:[A-Za-z0-9_.:-]{0,251}[A-Za-z0-9])?$")
_PROPERTY_PATTERN = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*(?:,[A-Za-z_][A-Za-z0-9_]*)*$")
_SERVICE_PATTERN = re.compile(r"^[A-Za-z0-9_.@-]{1,120}$")


def policy_summary() -> dict:
    return {
        "version": POLICY_VERSION,
        "mode": "diagnostic_allowlist",
        "title": "Mode diagnostic protégé",
        "description": (
            "Seules les commandes de diagnostic en lecture seule listées sont autorisées. "
            "Toute autre commande est refusée par l'API et par l'agent hôte."
        ),
        "allowed_groups": [
            {
                "title": "Système",
                "commands": [
                    "Get-CimInstance (classes système approuvées)",
                    "Get-Date, Get-Uptime, hostname, whoami, systeminfo",
                ],
            },
            {
                "title": "Linux",
                "commands": [
                    "uname, uptime, id, hostname, ps (noms de processus sans arguments)",
                    "df, free, lsblk, ip, ss, systemctl is-active/is-enabled",
                ],
            },
            {
                "title": "Processus et services",
                "commands": ["Get-Process, Get-Service, tasklist"],
            },
            {
                "title": "Stockage",
                "commands": ["Get-PSDrive -PSProvider FileSystem, Get-Volume"],
            },
            {
                "title": "Réseau",
                "commands": [
                    "Get-NetIPConfiguration, Get-NetAdapter, Get-NetTCPConnection, Get-NetRoute",
                    "ipconfig, netstat, ping, tracert, nslookup",
                    "Test-Connection, Test-NetConnection, Resolve-DnsName",
                ],
            },
            {
                "title": "Docker — vue extérieure uniquement",
                "commands": ["docker ps, docker stats --no-stream, docker version"],
            },
            {
                "title": "NVIDIA Jetson",
                "commands": [
                    "jetson-info (modèle, version L4T et noyau)",
                    "jetson-stats (charge et températures pendant 3 secondes)",
                ],
            },
            {
                "title": "Présentation des résultats",
                "commands": [
                    "Select-Object, Sort-Object, Measure-Object, Format-List, Format-Table"
                ],
            },
        ],
        "blocked_groups": [
            {
                "title": "Comptes et mots de passe",
                "examples": "passwd, net user, Set-LocalUser, comptes AD et clés SSH",
            },
            {
                "title": "Fichiers et données de l'application",
                "examples": "lecture, recherche, copie, modification, suppression, archive et partage de fichiers",
            },
            {
                "title": "Contenu interne de Docker",
                "examples": "docker exec, cp, inspect, logs, export, save et docker compose config",
            },
            {
                "title": "Modification de Docker",
                "examples": "run, build, pull, push, start, stop, restart, kill, rm, prune et volumes",
            },
            {
                "title": "Téléchargement et exfiltration",
                "examples": "curl, wget, Invoke-WebRequest, FTP, SCP, SMB et clients cloud",
            },
            {
                "title": "Exécution de code et contournement",
                "examples": "PowerShell imbriqué, cmd, bash, Python, Node, scripts, commandes encodées et .NET",
            },
            {
                "title": "Configuration du système",
                "examples": "registre, pare-feu, services, tâches planifiées, paquets, arrêt et redémarrage",
            },
            {
                "title": "Élévation et contrôle de processus",
                "examples": "sudo, runas, élévation UAC, Stop-Process et taskkill",
            },
        ],
    }


def _deny(category: str, message: str) -> None:
    raise TerminalPolicyViolation(category, message)


def _validate_common(command: str) -> str:
    normalized = str(command or "").strip()
    if not normalized:
        _deny("invalid", "La commande est vide.")
    if len(normalized.encode("utf-8")) > MAX_COMMAND_BYTES:
        _deny("invalid", "La commande dépasse 4 Ko.")
    for pattern, category, message in _BLOCKED_SYNTAX:
        if pattern.search(normalized):
            _deny(category, message)
    return normalized


def _tokens(segment: str) -> list[str]:
    return [token for token in segment.strip().split() if token]


def _safe_property_list(value: str) -> bool:
    if not _PROPERTY_PATTERN.fullmatch(value):
        return False
    return all(item.lower() in _SAFE_PROPERTIES for item in value.split(","))


def _validate_projection(name: str, args: list[str], position: int) -> None:
    if position == 0:
        _deny("policy", f"{name} doit suivre une commande de diagnostic autorisée.")
    lowered = [item.lower() for item in args]
    if name == "select-object":
        index = 0
        properties_seen = False
        while index < len(args):
            token = lowered[index]
            if token in {"-first", "-last", "-skip"}:
                if index + 1 >= len(args) or not args[index + 1].isdigit():
                    _deny("policy", "Paramètre Select-Object non autorisé.")
                index += 2
            elif token == "-unique":
                index += 1
            elif token == "-property":
                if index + 1 >= len(args) or not _safe_property_list(args[index + 1]):
                    _deny("secrets", "Cette propriété ne peut pas être affichée.")
                properties_seen = True
                index += 2
            elif _safe_property_list(args[index]) and not properties_seen:
                properties_seen = True
                index += 1
            else:
                _deny("secrets", "Cette propriété ou option Select-Object n'est pas autorisée.")
        return
    if name in {"format-list", "format-table"}:
        for token in args:
            if token.lower() in {"-autosize", "-wrap", "-hidetableheaders"}:
                continue
            if not _safe_property_list(token):
                _deny("secrets", "Cette propriété de formatage n'est pas autorisée.")
        return
    if name == "sort-object":
        properties = [item for item in args if not item.startswith("-")]
        options = [item.lower() for item in args if item.startswith("-")]
        if len(properties) > 1 or any(not _safe_property_list(item) for item in properties):
            _deny("policy", "Propriété Sort-Object non autorisée.")
        if any(item not in {"-ascending", "-descending", "-unique"} for item in options):
            _deny("policy", "Option Sort-Object non autorisée.")
        return
    if name == "measure-object":
        allowed_options = {"-average", "-maximum", "-minimum", "-sum"}
        index = 0
        while index < len(args):
            token = lowered[index]
            if token == "-property":
                if index + 1 >= len(args) or not _safe_property_list(args[index + 1]):
                    _deny("policy", "Propriété Measure-Object non autorisée.")
                index += 2
            elif token in allowed_options:
                index += 1
            else:
                _deny("policy", "Option Measure-Object non autorisée.")


def _validate_cim(args: list[str]) -> None:
    if len(args) == 1:
        class_name = args[0]
    elif len(args) == 2 and args[0].lower() == "-classname":
        class_name = args[1]
    else:
        _deny("secrets", "Seules les classes CIM système approuvées sont autorisées.")
    if class_name.lower() not in _SAFE_CIM_CLASSES:
        _deny("secrets", "Cette classe CIM peut exposer des données sensibles.")


def _validate_target_command(name: str, args: list[str]) -> None:
    if not args or not _HOST_PATTERN.fullmatch(args[0]):
        _deny("network", f"Cible {name} invalide.")
    remaining = args[1:]
    index = 0
    while index < len(remaining):
        option = remaining[index].lower()
        if option in {"-4", "-6", "-quiet", "-d"}:
            index += 1
        elif option in {"-count", "-n", "-port", "-h"}:
            if index + 1 >= len(remaining) or not remaining[index + 1].isdigit():
                _deny("network", f"Option {name} invalide.")
            value = int(remaining[index + 1])
            if option in {"-count", "-n"} and not 1 <= value <= 4:
                _deny("network", "Le nombre de requêtes est limité à 4.")
            if option == "-port" and not 1 <= value <= 65535:
                _deny("network", "Port réseau invalide.")
            if option == "-h" and not 1 <= value <= 32:
                _deny("network", "Le nombre de sauts est limité à 32.")
            index += 2
        elif option == "-informationlevel" and index + 1 < len(remaining):
            if remaining[index + 1].lower() not in {"quiet", "detailed"}:
                _deny("network", "Niveau d'information non autorisé.")
            index += 2
        else:
            _deny("network", f"Option {name} non autorisée.")


def _validate_docker(args: list[str]) -> None:
    lowered = [item.lower() for item in args]
    if lowered and lowered[0] == "ps" and all(item in {"-a", "--all"} for item in lowered[1:]):
        return
    if lowered in (["stats", "--no-stream"], ["stats", "--no-stream", "--all"], ["version"]):
        return
    _deny(
        "docker",
        "Docker est limité à ps, stats --no-stream et version. L'accès au contenu des conteneurs est interdit.",
    )


def _validate_powershell_segment(segment: str, position: int) -> None:
    words = _tokens(segment)
    if not words:
        _deny("invalid", "Segment de commande vide.")
    name = words[0].lower()
    args = words[1:]
    if name in _PIPELINE_COMMANDS:
        _validate_projection(name, args, position)
        return
    if position > 0:
        _deny("scripts", "Seules les commandes de présentation sont autorisées après un pipeline.")
    if name in _NO_ARGUMENT_POWERSHELL:
        if args:
            _deny("policy", f"Les options de {words[0]} ne sont pas autorisées.")
        return
    if name == "get-ciminstance":
        _validate_cim(args)
        return
    if name == "get-psdrive":
        if [item.lower() for item in args] not in ([], ["-psprovider", "filesystem"]):
            _deny("filesystem", "Get-PSDrive est limité aux volumes de fichiers.")
        return
    if name in {"test-connection", "test-netconnection", "resolve-dnsname"}:
        _validate_target_command(name, args)
        return
    if name == "hostname" and not args:
        return
    if name == "whoami" and all(item.lower() in {"/user", "/groups", "/priv", "/all"} for item in args):
        return
    if name == "systeminfo" and not args:
        return
    if name == "ipconfig" and [item.lower() for item in args] in ([], ["/all"]):
        return
    if name == "netstat" and all(item.lower() in {"-a", "-n", "-o", "-r", "-s", "-ano", "-rn"} for item in args):
        return
    if name == "tasklist" and [item.lower() for item in args] in ([], ["/svc"]):
        return
    if name in {"ping", "tracert", "nslookup"}:
        _validate_target_command(name, args)
        return
    if name in {"docker", "docker.exe"}:
        _validate_docker(args)
        return
    _deny("policy", f"La commande {words[0]} n'appartient pas au catalogue de diagnostic autorisé.")


def _validate_powershell(command: str) -> None:
    segments = [segment.strip() for segment in command.split("|")]
    if len(segments) > 4 or any(not segment for segment in segments):
        _deny("scripts", "Pipeline invalide ou trop complexe.")
    names = [_tokens(segment)[0].lower() for segment in segments]
    if names[0] == "get-ciminstance" and (len(names) < 2 or names[1] != "select-object"):
        _deny("secrets", "Une requête CIM doit sélectionner explicitement les propriétés autorisées.")
    projected = False
    for position, segment in enumerate(segments):
        words = _tokens(segment)
        name = words[0].lower()
        args = words[1:]
        if name in {"format-list", "format-table"}:
            explicit_properties = any(not item.startswith("-") for item in args)
            if not projected and not explicit_properties:
                _deny("secrets", "Le formatage doit préciser les propriétés à afficher.")
        _validate_powershell_segment(segment, position)
        if name == "measure-object":
            projected = True
        elif name == "select-object":
            projected = any(
                item.lower() == "-property"
                or (not item.startswith("-") and not item.isdigit())
                for item in args
            )


def _validate_posix(command: str) -> None:
    if "|" in command:
        _deny("scripts", "Les pipelines ne sont pas autorisés sur cet hôte.")
    words = _tokens(command)
    name = words[0].lower()
    args = words[1:]
    if name == "uname" and all(item in {"-a", "-s", "-r", "-m"} for item in args):
        return
    if name in {"uptime", "id", "hostname"} and not args:
        return
    if name == "df" and all(item in {"-h", "-t", "--total"} for item in args):
        return
    if name == "free" and all(item in {"-h", "-m", "-g"} for item in args):
        return
    if name == "lsblk" and not args:
        return
    if name == "ip" and [item.lower() for item in args] in (
        ["addr"], ["address"], ["route"], ["link"],
        ["addr", "show"], ["route", "show"], ["link", "show"],
    ):
        return
    if name == "ss" and all(re.fullmatch(r"-[alntup]+", item) for item in args):
        return
    if name == "ps" and args in (["-ef"], ["aux"]):
        return
    if name in {"ping", "traceroute", "nslookup", "dig"}:
        _validate_target_command(name, args)
        return
    if name == "docker":
        _validate_docker(args)
        return
    if name == "systemctl" and len(args) == 2 and args[0] in {"is-active", "is-enabled"} and _SERVICE_PATTERN.fullmatch(args[1]):
        return
    if name in {"jetson-info", "jetson-stats"} and not args:
        return
    _deny("policy", f"La commande {words[0]} n'appartient pas au catalogue de diagnostic autorisé.")


def validate_terminal_command(shell: str, command: str) -> str:
    normalized = _validate_common(command)
    normalized_shell = str(shell or "").lower()
    if normalized_shell == "powershell":
        _validate_powershell(normalized)
    elif normalized_shell in {"bash", "sh"}:
        _validate_posix(normalized)
    else:
        _deny("shell", "Ce shell n'est pas autorisé par la politique de sécurité.")
    return normalized

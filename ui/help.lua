--[[ CC_RSMP - ui/help.lua
  Texte d'aide général et aide contextuelle par commande.
]]
local Help = {}

Help.USAGE = [[
CC_Radio - CC Radio System Music Player

USAGE:
  CC_Radio <commande> [options]

COMMANDES:
  broadcaster        Demarrer une station radio (serveur)
  client             Se connecter a une station (recepteur)
  play <query|url>   Ajouter et jouer une chanson
  status             Afficher l'etat du broadcaster
  stop               Arreter la lecture
  volume <0.0-3.0>   Regler le volume (--local/--global)
  skip               Morceau suivant
  pause / resume     Pause / reprise
  prev               Morceau precedent
  loop [off|one|all] Mode de repetition
  shuffle [on|off]   Lecture aleatoire
  config             Voir/modifier la config (--show/--set/--reset)
  install            Installer / mettre a jour (--update)
  help [commande]    Cette aide, ou l'aide d'une commande

EXEMPLES:
  CC_Radio broadcaster --label "Ma Radio"
  CC_Radio client --id 5
  CC_Radio play --query "lofi hip hop" --local
  CC_Radio volume 1.5 --global
  CC_Radio help broadcaster
]]

Help.COMMANDS = {
  broadcaster = [[
BROADCASTER - Demarrer une station radio

Lance le programme en mode serveur. Telecharge la musique via l'API
Firebase/Cloud Run de terreng et la broadcast aux clients connectes.
Le broadcaster peut fonctionner SANS speaker (--no-speaker).
Un modem (wireless ou wired) est obligatoire.

OPTIONS:
  --label <nom>   Nom de la station (defaut: config.station_label)
  --no-speaker    Broadcaster sans jouer localement
  --gui           Forcer l'interface graphique (monitor requis)
  --local         Jouer localement sans broadcast (standalone)

EXEMPLES:
  CC_Radio broadcaster
  CC_Radio broadcaster --label "Ma Radio Lofi"
  CC_Radio broadcaster --no-speaker --gui
]],

  client = [[
CLIENT - Se connecter a une station radio

Lance le programme en mode recepteur. Recoit le flux audio du
broadcaster et le joue sur le speaker local.
Un speaker ET un modem sont OBLIGATOIRES en mode client.
Sans --id, le programme auto-detecte les stations (discovery).

OPTIONS:
  --id <n>        ID du broadcaster cible (sinon auto-discover)
  --volume <f>    Volume local 0.0-3.0 (defaut: config.local_volume)
  --gui           Forcer l'interface graphique (monitor requis)

EXEMPLES:
  CC_Radio client
  CC_Radio client --id 5
  CC_Radio client --volume 2.0
]],

  play = [[
PLAY - Ajouter et jouer une chanson

Recherche par texte ou URL, puis lecture. En mode broadcaster, diffuse
aux clients ; avec --local, joue uniquement en local (standalone).

OPTIONS:
  --query <texte> Recherche par texte
  --youtube <url> URL YouTube directe (resolution a valider)
  --next          Ajouter en tete de queue
  --local         Lecture locale uniquement

EXEMPLES:
  CC_Radio play --query "lofi hip hop" --local
  CC_Radio play --youtube https://youtu.be/dQw4w9WgXcQ
]],

  config = [[
CONFIG - Configuration persistante (config.json)

OPTIONS:
  --show              Afficher la config (defaut)
  --set <cle> <val>   Modifier un parametre
  --reset             Remettre les valeurs par defaut

EXEMPLES:
  CC_Radio config --show
  CC_Radio config --set chunk_size_kb 8
  CC_Radio config --reset
]],
}

--- Affiche l'aide générale ou celle d'une commande (paginée : scrollable dans le shell).
function Help.show(cmd)
  local text = (cmd and Help.COMMANDS[cmd]) or Help.USAGE
  textutils.pagedPrint(text)
end

return Help

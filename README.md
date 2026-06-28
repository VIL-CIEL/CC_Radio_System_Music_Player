# CC_RSMP — CC Radio System Music Player

> **Système de radio musicale in-game pour Minecraft** (CC: Tweaked / CraftOS).
> Recherche et streame de la musique YouTube (convertie en DFPWM via l'API de
> [terreng](https://github.com/terreng/computercraft-streaming-music)), la joue sur des
> speakers, et la **diffuse en réseau** (rednet) à des ordinateurs clients.

**Version : 1.0.0** · Licence MIT · Lua / CraftOS 1.9 · CC: Tweaked ≥ 1.100.0

---

## Sommaire
1. [Présentation](#présentation)
2. [Fonctionnalités](#fonctionnalités)
3. [Prérequis Minecraft](#prérequis-minecraft)
4. [Installation](#installation)
5. [Démarrage rapide](#démarrage-rapide)
6. [Modes de fonctionnement](#modes-de-fonctionnement)
7. [Commandes & contrôles](#commandes--contrôles)
8. [Configuration](#configuration)
9. [Fonctionnement interne](#fonctionnement-interne)
10. [Comment améliorer / étendre](#comment-améliorer--étendre)
11. [Dépannage](#dépannage)
12. [Développement](#développement)
13. [Crédits & licence](#crédits--licence)

---

## Présentation

CC_RSMP transforme des ordinateurs ComputerCraft en **station de radio**. Un ordinateur
*broadcaster* télécharge la musique et la diffuse ; des ordinateurs *clients* la reçoivent
et la jouent sur leurs propres enceintes. On peut aussi l'utiliser en **solo** (lecture
locale sans réseau).

L'audio circule au format **DFPWM** (le format audio natif de ComputerCraft). Le broadcaster
envoie les chunks bruts ; chaque client les décode localement — efficace en bande passante.

## Fonctionnalités

- 🔎 Recherche YouTube par mots-clés ou lecture directe par URL/ID.
- 🔊 Lecture multi-speakers avec contrôle du volume (0.0–3.0).
- 📻 Diffusion réseau (rednet) **un-vers-plusieurs** : 1 broadcaster, N clients.
- 🎚️ Playlist complète : file d'attente, **shuffle**, **loop** (off/one/all), historique.
- 🖥️ Double interface : **CLI** (terminal) et **GUI tactile** (monitor) — utilisables simultanément.
- 🛰️ Découverte automatique de station + heartbeat ; reconnexion auto en cas de perte de signal.
- 🎛️ Télécommande : un client peut piloter le broadcaster (volume, status…).
- 💾 Configuration et playlist persistantes.
- 📦 Installeur one-liner + mise à jour.

## Prérequis Minecraft

| Élément | Détail |
|---|---|
| Mod | **CC: Tweaked ≥ 1.100.0** (Forge ou Fabric) — pour l'API audio `cc.audio.dfpwm`. |
| Ordinateur | **Advanced Computer** recommandé (couleurs + GUI monitor). |
| Modem | Wireless ou wired — **obligatoire** en broadcaster/client. |
| Speaker | **Obligatoire** en client ; optionnel en broadcaster (mode `--no-speaker`). |
| Monitor (Advanced) | Optionnel — active l'interface graphique tactile. |
| HTTP | `http_enabled = true` côté serveur, et l'API autorisée (whitelist). |

## Installation

**One-liner** (sur l'ordinateur, dans le shell) :

```
wget https://raw.githubusercontent.com/VIL-CIEL/CC_Radio_System_Music_Player/main/install.lua install.lua
install
```

L'installeur télécharge tous les fichiers du programme. Pour **mettre à jour** plus tard :

```
CC_Radio install
```

> Installation manuelle : copiez `CC_Radio.lua` et les dossiers `core/`, `ui/`, `lib/` à la
> racine de l'ordinateur.

## Démarrage rapide

```
-- Station radio (serveur)
CC_Radio broadcaster --label "Ma Station"

-- Récepteur (sur un autre ordinateur, avec speaker)
CC_Radio client

-- Lecture solo, sans réseau
CC_Radio play --query "lofi hip hop" --local
```

## Modes de fonctionnement

- **Broadcaster** (`CC_Radio broadcaster`) : télécharge, joue localement (sauf `--no-speaker`)
  et **diffuse** aux clients. Gère la playlist, les métadonnées et les commandes distantes.
- **Client** (`CC_Radio client`) : découvre/rejoint une station, reçoit le flux, le décode et
  le joue. Volume **local indépendant**. Auto-reconnexion.
- **Local / standalone** (`CC_Radio play --local` ou `CC_Radio local`) : lecteur solo sans réseau.

## Commandes & contrôles

### Commandes shell

| Commande | Description |
|---|---|
| `broadcaster [--label N] [--no-speaker] [--gui] [--local]` | Démarrer une station |
| `client [--id N] [--volume F] [--gui]` | Rejoindre une station |
| `play <query> [--local] [--youtube URL]` | Jouer / diffuser une chanson (raccourci broadcaster) |
| `queue [--add Q] [--list] [--clear]` | Gérer la file (persistée) |
| `loop [off\|one\|all]` · `shuffle [on\|off]` | Modes de lecture |
| `volume <0.0-3.0> [--local\|--global]` | Régler le volume |
| `config [--show] [--set K V] [--reset]` | Configuration |
| `install` | Installer / mettre à jour |
| `help [commande]` | Aide |

> `skip`/`pause`/`resume`/`prev`/`stop`/`status` en shell autonome renvoient une aide : ces
> actions se font **au clavier** dans le lecteur, ou **en réseau** (client → broadcaster).

### Raccourcis clavier (lecteur / broadcaster)

`P` pause · `S` skip · `B` précédent · `+`/`-` volume · `L` loop · `Z` shuffle · `Q` voir la file · `A` ajouter · `X` quitter

### Client

`+`/`-` volume local · `G` envoyer le volume au broadcaster (global) · `S` status · `X` déconnexion

### GUI tactile (monitor)

Boutons tactiles : broadcaster `<< |> >> SHUF LOOP` ; client `VOL- VOL+ STAT DISC`.
Le GUI s'active automatiquement si un monitor est présent (mode **dual** avec la CLI), ou via `--gui`.

## Configuration

Fichier `config.json` (généré à la première sauvegarde). Clés principales :

| Clé | Défaut | Rôle |
|---|---|---|
| `station_label` | `"CC Radio"` | Nom de la station |
| `default_volume` / `local_volume` | `1.0` | Volume broadcaster / client |
| `loop` / `shuffle` | `"off"` / `false` | Modes par défaut |
| `api_url` | endpoint terreng | API de streaming (self-host possible) |
| `api_version` | `"2.1"` | Version d'API attendue |
| `rednet_protocol_prefix` | `"CC_RSMP"` | Préfixe des protocoles rednet |
| `audio_encoding` | `"base64"` | `base64` (~1.34×) ou `raw` (~3.2×) sur le réseau |
| `chunk_size_kb` | `16` | Taille des chunks DFPWM |
| `http_retries` | `2` | Tentatives HTTP supplémentaires |
| `meta_interval_sec` / `discovery_interval_sec` | `5` / `30` | Cadence META / annonce |
| `max_queue_size` / `history_size` | `50` / `10` | Limites file / historique |

Exemple : `CC_Radio config --set audio_encoding raw`

## Fonctionnement interne

### Pipeline audio

```
Recherche : GET api_url?v=<ver>&search=<query>          -> JSON {id,name,artist,type}
Téléchargement : GET api_url?v=<ver>&id=<id> (binary)   -> flux DFPWM
  (lecture : 4 octets d'en-tête + chunks de 16 KiB)
DFPWM --[cc.audio.dfpwm decoder]--> PCM --[speaker.playAudio + backpressure]--> son
```

### Diffusion réseau

Le broadcaster **n'envoie pas le PCM** (≈131 072 valeurs/chunk) mais le **chunk DFPWM brut**
(16 KiB), encodé en base64 pour limiter le gonflement de sérialisation rednet (≈1.34× au lieu
de ≈3.2×). Chaque client décode localement.

| Protocole | Sens | Contenu |
|---|---|---|
| `CC_RSMP_AUDIO` | broadcaster → clients | chunks `{seq, song_id, data, encoding}` + `audio_stop` |
| `CC_RSMP_META` | broadcaster → clients | titre, artiste, position, volume, état, file (toutes les 5 s) |
| `CC_RSMP_CMD` | client → broadcaster | commandes (`pause`, `volume`, `status`…) |
| `CC_RSMP_ACK` | broadcaster → client | accusés de réception |
| `CC_RSMP_DISCO` | bidirectionnel | `announce` (30 s) / `join` |

Les clients suivent les numéros de séquence (`seq`) pour **compter les pertes**, et basculent en
redécouverte après 5 s sans message.

### Architecture des modules

```
CC_Radio.lua        Point d'entrée : parsing CLI, routage, garde anti-crash + log
core/
  downloader.lua    Recherche + streaming HTTP (retry), objet Stream
  audio.lua         Décodage DFPWM, playback multi-speakers, volume
  playlist.lua      File, shuffle, loop, historique, persistance (queue.dat)
  player.lua        Lecteur local interactif
  broadcaster.lua   Serveur : 5 boucles parallèles + handler de commandes
  client.lua        Récepteur : réception/décodage/playback + resync
  network.lua       Protocoles rednet, encodage des chunks
  prereq.lua        Détection matériel + version
ui/
  cli.lua           Rendu terminal (lecteur, broadcaster, client, file)
  gui.lua           Layouts monitor + mapping tactile
  widgets.lua       Boutons, barres, hit-testing
  help.lua          Aide
lib/
  config.lua  logger.lua  utils.lua  base64.lua  discovery.lua
install.lua         Installeur / updater autonome
```

> Concurrence : broadcaster et client reposent sur `parallel.waitForAny`, chaque boucle cédant
> la main à chaque `os.pullEvent`/`sleep`/backpressure speaker (modèle coopératif de CraftOS).

## Comment améliorer / étendre

Points d'extension les plus accessibles :

- **Ajouter une commande shell** : créez `cmdXxx(cfg, parsed)` dans `CC_Radio.lua` et ajoutez
  une branche dans `main`. Documentez-la dans `ui/help.lua`.
- **Ajouter une commande réseau** : gérez le nouveau `command` dans `applyCommand` (broadcaster)
  et émettez-le côté client via `net:sendCmd`.
- **Nouveau bouton GUI** : ajoutez une entrée à `GUI.BROADCASTER_ITEMS` / `GUI.CLIENT_ITEMS`
  (id = nom d'action) ; l'action est routée par `doAction` dans broadcaster/client.
- **Self-hoster l'API** : déployez votre instance Firebase de terreng et changez `api_url`
  (`CC_Radio config --set api_url <votre-url>`). Voir le dépôt de terreng pour le guide.
- **Sécuriser le réseau** (rednet n'est pas chiffré) : ajouter un token de session partagé,
  vérifié dans `applyCommand` et inclus dans les messages — piste pour une v1.1.
- **Synchronisation fine** : la lecture clients n'est pas alignée à la milliseconde (acceptable
  pour une radio) ; un buffering basé sur `chunk_seq`/horloge pourrait l'améliorer.

Avant toute contribution : lancez l'analyse statique (LuaLS) et les tests émulés (voir ci-dessous).

## Dépannage

| Symptôme | Cause probable / solution |
|---|---|
| « CC: Tweaked >= 1.100.0 requis » | Mod trop ancien ; mettez à jour. |
| « Aucun modem détecté » | Attachez/équipez un modem (wireless ou wired). |
| « Aucun speaker détecté » (client) | Un speaker est obligatoire côté client. |
| Recherche/téléchargement échoue | HTTP désactivé ou API non whitelistée côté serveur. |
| GUI inactif | Pas de monitor, ou monitor trop petit (min ~26×12 à l'échelle 0.5). |
| Audio saccadé chez les clients | Réseau saturé : passez `chunk_size_kb` à 8, ou gardez `audio_encoding=base64`. |
| Une « pub Patreon » apparaît en recherche | L'API terreng injecte une entrée promo ; le sélecteur choisit par défaut le 1er vrai titre. |

Les erreurs sont journalisées dans `CC_Radio.log`.

## Développement

- **Émulateur** : [CraftOS-PC](https://www.craftos-pc.cc) (mode headless) pour exécuter/tester hors-jeu.
- **Analyse statique** : [LuaLS](https://luals.github.io) (config `.luarc.json` fournie).
- **Roadmap & historique** : [docs/ROADMAP.md](docs/ROADMAP.md) (développement par sprints, versions `vMajeur.Mineur.Fix`).
- **Démarrage auto** : voir [docs/startup.example.lua](docs/startup.example.lua) (auto-restart au boot).

## Crédits & licence

- **Source audio & API** : [terreng/computercraft-streaming-music](https://github.com/terreng/computercraft-streaming-music) (MIT) — voir [CREDITS.md](CREDITS.md).
- **Plateforme** : [CC: Tweaked](https://tweaked.cc).
- **Licence** : MIT (voir [LICENSE](LICENSE)).

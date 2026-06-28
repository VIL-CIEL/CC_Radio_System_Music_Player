# CC_RSMP — Feuille de route (Sprints)

> 1 Sprint = 1 fonctionnalité livrable et taggée. Versioning `v.Majeur.Mineur.Fix`.
> Les sprints montent le **Mineur** (`v0.1.0` → `v0.6.0`) ; la release finale = `v1.0.0`.
> Un correctif en cours de sprint monte le **Fix** (`v0.4.1`, `v0.4.2`, …).
> Travail 100 % local (aucun push automatique).

## Vue d'ensemble

| Sprint | Version | Fonctionnalité | Statut |
|---|---|---|---|
| S0 | `v0.1.0` | Fondations : structure, entry point, prérequis, config/logger/utils, parsing CLI, aide | ✅ Fait |
| S1 | `v0.2.0` | Audio local standalone (download → decode → play) | ✅ Fait |
| S2 | `v0.3.0` | Playlist + contrôles CLI interactifs + persistance | ✅ Fait |
| S3 | `v0.4.0` | Broadcaster réseau (audio/meta/cmd/disco) | ✅ Fait |
| S4 | `v0.5.0` | Client réseau (réception, décodage, resync) | ✅ Fait |
| S5 | `v0.6.0` | GUI Monitor (widgets, layouts, touch, mode dual) | ✅ Fait |
| S6 | `v1.0.0` | Polish, installeur, robustesse, README final | ✅ Fait |

## Détail des sprints

### S0 — Fondations & Bootstrap (`v0.1.0`) ✅
- Structure de dossiers (code à la racine du repo), entry point `CC_Radio.lua` + routeur de modes.
- `lib/config.lua`, `lib/logger.lua`, `lib/utils.lua`.
- `core/prereq.lua` : vérif CC:T ≥ 1.100 + détection modem/speaker/monitor.
- `ui/help.lua` : aide générale + par commande.
- Docs : README, CREDITS (terreng), ROADMAP, `.luarc.json` (LuaLS).
- **Spike réseau levé** : sérialisation rednet d'un chunk DFPWM binaire — round-trip
  intègre, inflation ~3,2× (16 KiB → ~52 Ko sérialisé). 16 KiB validé ; optimisation
  base64 (~1,33×) à évaluer en S3.

### S1 — Audio Local Standalone (`v0.2.0`) ✅
- `core/downloader.lua` : recherche `?v=2.1&search=` (JSON), download `?v=2.1&id=` (`binary=true`),
  streaming header 4 octets + chunks `16*1024-4` puis `16*1024`.
- `core/audio.lua` : `dfpwm.make_decoder`, `speaker.playAudio` + backpressure `speaker_audio_empty`,
  volume 0.0–3.0, multi-speakers (`parallel.waitForAll`).
- `ui/cli.lua` : sélecteur de résultats + écran "lecture en cours" (titre/artiste/progression/volume).
- `CC_Radio play --query "lofi" --local` et `--youtube <url>` fonctionnels.
- **Validé sur l'API en direct** (CraftOS-PC) : recherche, download, décodage 131072 samples/chunk,
  promo Patreon de l'API écartée automatiquement. Rendu audible : à confirmer in-game.
- Notes : `id` API = identifiant vidéo YouTube ; `urlEncode` encode l'espace en `+` (OK pour l'API).

### S2 — Playlist & Contrôles CLI (`v0.3.0`) ✅
- `core/playlist.lua` : queue, shuffle, loop (off/one/all), history, maxQueue ; persistance `queue.dat`.
- `core/player.lua` : lecteur local interactif (`parallel.waitForAny(audioLoop, inputLoop)`),
  pause/skip/prev réactifs via `audio:stop()`, ajout de chanson en cours de lecture.
- `ui/cli.lua` : `drawPlayer` (modes/queue/progression) + `showQueue`/`printQueue`.
- Commandes shell persistées : `queue --add/--list/--clear`, `loop`, `shuffle`, `volume` (--local/--global).
  `play --local` et `local` lancent le lecteur ; `skip/pause/...` en autonome renvoient une aide
  (actionnables au clavier en lecture, ou en réseau S3/S4).
- Touches lecteur : P pause · S skip · B prev · +/- volume · L loop · Z shuffle · Q queue · A add · X exit.
- Validation : 39/39 tests headless (logique + commandes persistées + smoke lecteur), LuaLS clean.

### S3 — Broadcaster Réseau (`v0.4.0`) ✅
- **Encodage tranché : base64 par défaut** (~1,34× vs 3,23× raw ; ~6 ms encode/décode). `lib/base64.lua`.
- `core/network.lua` : protocoles `CC_RSMP_AUDIO/META/CMD/ACK/DISCO`, encode/decode chunk, transport rednet.
- `core/broadcaster.lua` : `parallel.waitForAny(audioLoop, networkLoop, metaLoop, discoveryLoop, uiLoop)`,
  état partagé + handler de commandes unique (clavier local ET rednet distant).
- Broadcast chunks DFPWM + `seq`, audio_stop, META (5 s), DISCO announce (30 s) + prune clients,
  exécution CMD (pause/resume/skip/prev/stop/volume/loop/shuffle/play/queue/status) + ACK, `--no-speaker`
  (cadençage manuel ~ temps réel quand pas de lecture locale).
- `play` sans `--local` = raccourci broadcaster ; `broadcaster --local` = lecture solo.
- Validation : 17/17 headless (base64/réseau + resolveSong live + smoke broadcaster complet avec
  modem/speaker émulés, stream simulé, CMD injecté). LuaLS clean.
- ⚠️ Sync réelle broadcaster↔client à valider en jeu (1 ordi émulé = 1 identité rednet) — fait en S4.

### S4 — Client Réseau (`v0.5.0`) ✅
- `core/client.lua` : `parallel.waitForAny(netLoop, playLoop, uiLoop)`, handler `Client.handle`
  extrait (testable), décodage base64+DFPWM -> buffer PCM -> playback, volume local indépendant.
- `lib/discovery.lua` : auto-découverte via DISCO announce (ou `--id`), envoi du join.
- Gestion des trous de `seq` (compteur de pertes), reset au changement de chanson,
  perte de signal (timeout 5 s -> redécouverte).
- UI client : `+/-` volume local, `G` volume global (CMD), `S` status, `X` déconnexion.
- Validation : 16/16 headless (handle unitaire + discovery + smoke complet annonce/join/chunks/playback).
  LuaLS clean. Protocole compatible broadcaster par construction (mêmes shapes Network).
- ⚠️ Sync réelle 2 machines : à valider en jeu.

### S5 — GUI Monitor (`v0.6.0`) ✅
- `ui/widgets.lua` : hit-testing (pur/testable), `drawButton`, `hbar`, `buttonRow` responsive.
- `ui/gui.lua` : détection monitor + taille (min 26×12, scale 0.5), layouts broadcaster/client,
  `handleTouch` (coord → id d'action), rendu.
- Intégration broadcaster + client : `doAction` unique partagé clavier/tactile, gestion `monitor_touch`,
  **mode dual** (CLI terminal + GUI monitor simultanés), `--gui` force (erreur si pas de monitor).
- Boutons broadcaster : prev/playpause/skip/shuffle/loop ; client : vol-/vol+/status/disconnect.
- Validation : 17/17 headless (widgets + GUI sur monitor simulé + intégration `monitor_touch`). LuaLS clean.
- ⚠️ Rendu visuel & tactile réels : à valider en jeu.

### S6 — Polish & Distribution (`v1.0.0`) ✅
- `install.lua` autonome (wget) + commande `install` (téléchargement + maj de tous les fichiers).
- Robustesse : retry HTTP (`http_retries`), reconnexion client auto (S4), garde anti-crash globale
  (pcall + journalisation `CC_Radio.log`, ignore Ctrl+T).
- `docs/startup.example.lua` : auto-restart au boot.
- README final complet (présentation, install, commandes, config, fonctionnement interne,
  protocole, guide d'extension, dépannage, crédits terreng).
- Validation : 12/13 + 5/5 headless (retry HTTP, régression routage, installeur + makeDir). LuaLS clean.

## Reste à valider en jeu (non testable en headless)
- Rendu audio audible (broadcaster local + clients).
- Synchro réelle broadcaster ↔ client sur 2+ machines (rednet réel).
- Rendu visuel et tactile du GUI monitor.

## Idées post-1.0 (v1.1+)
- Sécurité réseau (token de session partagé) — rednet non chiffré.
- Synchronisation plus fine des clients (buffer basé sur seq/horloge).
- Stubs de types CC:T pour LuaLS (autocomplétion complète).

## Risques techniques suivis
- **Sérialisation binaire rednet** (levé en S0, à re-mesurer en jeu en S3).
- **Saturation queue d'événements** (256) côté broadcaster sous charge réseau.
- **Latence inter-clients** : non synchronisé à la ms — acceptable pour une radio (hors scope v1).
- **Résolution `--youtube`** : l'API terreng attend un `id` issu de la recherche ; la prise
  en charge d'une URL YouTube brute est à valider (S1).

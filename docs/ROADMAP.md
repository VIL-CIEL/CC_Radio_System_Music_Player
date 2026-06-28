# CC_RSMP — Feuille de route (Sprints)

> 1 Sprint = 1 fonctionnalité livrable et taggée. Versioning `v.Majeur.Mineur.Fix`.
> Les sprints montent le **Mineur** (`v0.1.0` → `v0.6.0`) ; la release finale = `v1.0.0`.
> Un correctif en cours de sprint monte le **Fix** (`v0.4.1`, `v0.4.2`, …).
> Travail 100 % local (aucun push automatique).

## Vue d'ensemble

| Sprint | Version | Fonctionnalité | Statut |
|---|---|---|---|
| S0 | `v0.1.0` | Fondations : structure, entry point, prérequis, config/logger/utils, parsing CLI, aide | ✅ Fait |
| S1 | `v0.2.0` | Audio local standalone (download → decode → play) | ⏳ À venir |
| S2 | `v0.3.0` | Playlist + contrôles CLI interactifs + persistance | ⏳ |
| S3 | `v0.4.0` | Broadcaster réseau (audio/meta/cmd/disco) | ⏳ |
| S4 | `v0.5.0` | Client réseau (réception, décodage, resync) | ⏳ |
| S5 | `v0.6.0` | GUI Monitor (widgets, layouts, touch, mode dual) | ⏳ |
| S6 | `v1.0.0` | Polish, installeur, robustesse, README final | ⏳ |

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

### S1 — Audio Local Standalone (`v0.2.0`)
- `core/downloader.lua` : recherche `?v=2.1&search=` (JSON), download `?v=2.1&id=` (`binary=true`),
  streaming header 4 octets + chunks `16*1024-4` puis `16*1024`.
- `core/audio.lua` : `dfpwm.make_decoder`, `speaker.playAudio` + backpressure `speaker_audio_empty`,
  volume 0.0–3.0, multi-speakers.
- `ui/cli.lua` : affichage titre/artiste/progression/volume.
- Cible : `CC_Radio play --query "lofi" --local` joue un morceau complet.

### S2 — Playlist & Contrôles CLI (`v0.3.0`)
- `core/playlist.lua` : queue, shuffle, loop (off/one/all), history.
- `ui/cli.lua` interactif (touches P/S/B/+/-/L/Z/Q/A/X).
- Commandes shell : queue/skip/pause/resume/prev/volume/loop/shuffle.
- Persistance `queue.dat` (`textutils.serialize`).

### S3 — Broadcaster Réseau (`v0.4.0`)
- Lever le choix d'encodage (raw vs base64) via mesure en jeu.
- `core/network.lua` : protocoles `CC_RSMP_AUDIO/META/CMD/ACK/DISCO`.
- `core/broadcaster.lua` : `parallel.waitForAll(audioLoop, networkLoop, uiLoop, discoveryLoop)`.
- Broadcast chunks + `seq`, META (5 s), DISCO (30 s), exécution des CMD, `--no-speaker`.

### S4 — Client Réseau (`v0.5.0`)
- `core/client.lua` : écoute, décodage local, playback, volume local indépendant.
- `lib/discovery.lua` : auto-découverte.
- Gestion paquets manquants (`seq`), perte de signal (timeout → redécouverte).
- CMD client → broadcaster (local vs `--global`).

### S5 — GUI Monitor (`v0.6.0`)
- `ui/widgets.lua`, `ui/gui.lua` (layouts broadcaster/client).
- Auto-détection monitor + taille (≥51×19), `--gui`, `monitor_touch`, mode dual.

### S6 — Polish & Distribution (`v1.0.0`)
- `install.lua` (wget/pastebin), `--update`.
- Robustesse : retry HTTP, reconnexion client, gestion d'erreurs globale + logger.
- README final (fonctionnement, installation, prérequis MC, guide d'amélioration, crédits).

## Risques techniques suivis
- **Sérialisation binaire rednet** (levé en S0, à re-mesurer en jeu en S3).
- **Saturation queue d'événements** (256) côté broadcaster sous charge réseau.
- **Latence inter-clients** : non synchronisé à la ms — acceptable pour une radio (hors scope v1).
- **Résolution `--youtube`** : l'API terreng attend un `id` issu de la recherche ; la prise
  en charge d'une URL YouTube brute est à valider (S1).

# CC_RSMP — CC Radio System Music Player

> Système de **radio musicale in-game** pour Minecraft (CC: Tweaked / CraftOS).
> Streame de la musique YouTube (via l'API de [terreng](https://github.com/terreng/computercraft-streaming-music),
> convertie en DFPWM), la joue sur des speakers et la **broadcast** à des ordinateurs
> clients via modem rednet.

🚧 **En développement** — voir l'avancement dans [docs/ROADMAP.md](docs/ROADMAP.md).
Sprint courant : **S0 — Fondations (`v0.1.0`)**.

---

## Modes (cible v1.0)

- **Broadcaster** — serveur radio : télécharge, joue (optionnel) et diffuse aux clients.
- **Client** — récepteur : reçoit le flux et le joue sur son speaker.
- **Local (standalone)** — lecture solo sans réseau.

## Prérequis Minecraft

- CC: Tweaked **≥ 1.100.0** (Forge ou Fabric).
- Advanced Computer recommandé (couleurs + GUI monitor).
- Modem (wireless ou wired) — obligatoire en broadcaster/client.
- Speaker — obligatoire en client, optionnel en broadcaster.
- `http_enabled = true` côté serveur + domaine de l'API autorisé.

## Utilisation (aperçu)

```
CC_Radio help                         -- aide
CC_Radio config --show                -- configuration courante
CC_Radio broadcaster --label "Radio"  -- (à venir) démarrer une station
CC_Radio client --id 5                -- (à venir) rejoindre une station
CC_Radio play --query "lofi" --local  -- (à venir) lecture solo
```

> En `v0.1.0`, seules `help` et `config` sont fonctionnelles ; les autres commandes
> annoncent le sprint où elles arrivent.

## Structure du projet

```
CC_Radio.lua        Point d'entrée (parsing args, routage des modes)
core/               Logique métier (audio, réseau, playlist, broadcaster, client...)
ui/                 Interfaces (CLI, GUI monitor, aide, widgets)
lib/                Utilitaires (config, logger, utils, discovery)
config.json         Configuration persistante (générée à la 1re sauvegarde)
docs/ROADMAP.md     Feuille de route par sprints
```

## Développement

Tests hors-jeu via **CraftOS-PC** (mode headless) et analyse statique via **LuaLS**
(config `.luarc.json` fournie). Voir [docs/ROADMAP.md](docs/ROADMAP.md) pour le plan
de développement et les risques techniques suivis.

Un guide « comment améliorer / étendre » détaillé sera fourni dans le README final (S6).

## Crédits & licence

Code sous licence **MIT** (voir `LICENSE`). Source audio et API : **terreng** —
voir [CREDITS.md](CREDITS.md).

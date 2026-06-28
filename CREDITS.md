# Crédits

## Source audio & API de streaming

CC_RSMP s'appuie sur le service de streaming de **terreng** pour la recherche
et le téléchargement audio (YouTube → DFPWM) :

- **Projet** : [terreng/computercraft-streaming-music](https://github.com/terreng/computercraft-streaming-music)
- **Licence** : MIT
- **Rôle** : API HTTP (Firebase Cloud Functions / Cloud Run) qui télécharge les
  vidéos YouTube via RapidAPI (YT-API) et renvoie un flux DFPWM consommable par
  `cc.audio.dfpwm`.

CC_RSMP utilise l'endpoint public de ce service par défaut. L'API reste la
propriété de son auteur ; merci de respecter sa licence et, si possible, de
**self-héberger** votre propre instance Firebase pour un usage intensif (voir le
dépôt de terreng pour le guide de déploiement).

> Toute réutilisation du code ou de l'API de terreng doit conserver cette
> attribution conformément à la licence MIT.

## Technologies

- [CC: Tweaked](https://tweaked.cc) — ComputerCraft pour Minecraft.
- [CraftOS-PC](https://www.craftos-pc.cc) — émulateur utilisé pour les tests hors-jeu.

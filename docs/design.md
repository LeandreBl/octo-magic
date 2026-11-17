# Octo Magic — décisions de design

## Plateformes et technique
- PC, téléphone (Android/iOS) et navigateur, depuis un seul projet **Godot 4 / GDScript**.
- Jeu **hors ligne**. Connexion requise seulement pour : créer un parchemin, envoyer un score au classement, synchroniser le compte.
- Contrôles twin-stick : clavier/souris, manette, double joystick tactile.
- Backend minimal : Supabase (comptes, Postgres) + fonction serverless qui appelle l'IA (Claude, sortie JSON contrainte).

## Boucle de jeu
- Vue de dessus, vagues d'ennemis croissantes, boss toutes les N vagues.
- XP en run → level up → choix d'une amélioration.
- Mort permanente : la run est perdue, l'or est conservé.
- Or → boutique entre les runs (bâtons, robes, anneaux) + bonus permanents.
- Succès, déblocages, scores, classement (local d'abord).

## Personnage
- Pas de classes : chaque joueur personnalise son mage (apparence + équipement).
- Sorts de base élémentaires (feu, glace, foudre, poison, arcane…), assets faits maison.

## Sorts
- Emplacements : sort principal, sort secondaire, ultime.
- Améliorations par sort : vitesse du projectile (si pertinent), nombre de projectiles, coût en mana, dégâts, cadence, zone…
- Inspiration : sorts de base et augments de Solomon's Boneyard, **avec nos noms, nos valeurs et nos visuels** (on reprend la mécanique, pas le contenu).

## Parchemins (cœur du jeu)
- La boucle de jeu est **toujours hors ligne** (sauf la coop P2P). La forge a lieu **entre deux runs**, jamais pendant (décision tâche #75).
- En run, on trouve des parchemins vierges : ils sont gardés. À la fin de la run (dans le hub), le joueur en écrit un avec un mot libre.
- Le mot part à la forge (modération, puis IA) qui renvoie un **bundle `.spell`** : un zip avec `manifest.json` (le sort : briques connues du moteur, forme, trajectoire, élément, effets) et les planches PNG de ses sprites.
- Le moteur calcule un **budget de puissance** : l'IA décrit, le moteur équilibre.
- Temps d'attente façon Clash of Clans pendant l'écriture : le joueur peut relancer une run en attendant ; le nouveau sort est équipé au début de la run suivante, jamais en cours de run.
- Le sort est lié au compte, stocké en local, jouable hors ligne.

### Art des sorts
- Claude écrit le sort et des **fiches artistiques** (`icon_brief`, et par projectile `look` et `burst`).
- **PixelLab** dessine : VFX animé du projectile (2 premiers projectiles du sort), impact du projectile principal, icône. 2 à 4 générations par sort.
- Repli : les grilles de pixels écrites par Claude, si PixelLab échoue ou n'a plus de crédits.
- **Classement** : local pour l'instant. En ligne plus tard : le serveur signera chaque sort, un score ne sera accepté qu'avec des sorts signés.

## Direction artistique
- Pixel art, univers heroic fantasy, sprites petits et peu détaillés.
- Jeu en **haute résolution** : tout est en pixel art (personnages, ennemis, sorts, décor plus grand), agrandi d'un facteur entier sans lissage (filtre « nearest », pas de flou).
- Sorts et effets aussi en pixel art, à la même taille de pixel que les sprites : effets procéduraux calés sur la grille de pixels (couche rendue en basse résolution puis agrandie sans lissage) ; l'interface et le texte restent en haute résolution.
- Piste : la forge peut aussi générer un petit sprite pixel art par sort (projectile, icône).
- Assets générés par IA (outils spécialisés pixel art) puis nettoyés à la main (grille, palette commune).

## Multijoueur (piste)
- **Coopération** : les joueurs affrontent les vagues ensemble.
- P2P avec un joueur hôte qui fait tourner la partie (le même moteur), les autres sont clients : pas de code serveur de jeu.
- Web et natif : WebRTC (Godot `WebRTCMultiplayerPeer`) ; un petit serveur de signalisation sert uniquement à mettre les joueurs en relation. Réseau local natif possible en ENet.
- Les sorts sont des données : un joueur envoie son JSON à l'hôte, qui le nettoie (`Spell.sanitize`) et le simule.

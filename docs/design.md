# Octo Magic — décisions de design

## Plateformes et technique
- PC, téléphone (Android/iOS) et navigateur, depuis un seul projet **Godot 4 / GDScript**.
- Jeu **hors ligne**. Connexion requise seulement pour : créer un parchemin, envoyer un score au classement, synchroniser le compte.
- Contrôles twin-stick : clavier/souris, manette, double joystick tactile.
- Backend minimal (tâche #86) : serveur Node (`backend/`), login **Firebase**, profils et sorts en **Postgres**, forge (IA) derrière le login, export web du jeu, relais coop dans son conteneur ; le tout lancé par `docker compose`.

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
- En run, on trouve des parchemins vierges : ils sont gardés. À la fin de la run (dans le hub), le joueur en écrit un ou plusieurs d'un coup : un mot libre par parchemin, séparés par des espaces ou des virgules (tâche #85).
- Parser strict côté forge : lettres, `'` et `-` seulement, autant de mots que de parchemins (8 max) ; sinon refusé avant l'IA, parchemins intacts.
- Un mot qui ne veut rien dire est **annulé** par l'IA : il ne change pas le sort et son parchemin est rendu.
- Anti-injection : les mots et le sort envoyés par le joueur sont passés à l'IA comme données balisées (`<` et `>` échappés), jamais comme instructions ; la sortie reste nettoyée et équilibrée par le moteur.
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

## Multijoueur
- **Coopération** : les joueurs affrontent les vagues ensemble (4 max, hôte compris).
- Un joueur hôte fait tourner la partie (le même moteur), les autres sont clients : pas de code serveur de jeu. Solo = un hôte seul.
- Web et natif : un **relais WebSocket** (`relay/`, Python stdlib) au lieu de WebRTC (tâche #78) : il passe les NAT sans STUN/TURN et ne fait que router les paquets d'un salon (code court). Côté Godot, `RelayPeer` (`MultiplayerPeerExtension`) donne l'API haut niveau (RPC, `MultiplayerSpawner`, `MultiplayerSynchronizer`).
- L'hôte fait autorité sur les ennemis, leurs tirs, les drops, les PV, le mana et les dégâts ; chaque joueur déplace et vise son mage lui-même (réactif malgré la latence du relais). Les sorts lancés sont rejoués chez les autres pour l'affichage seulement. La carte (et sa graine) est envoyée à tous.
- Chaque joueur garde sa propre run (niveau, améliorations, sorts) ; les ennemis tués et les drops ramassés comptent pour tout le monde. Pas de pause au level-up en coop.
- Les sorts sont des données : un joueur envoie ses sorts en JSON à l'hôte, qui les nettoie (`Spell.sanitize`), calcule leur coût et les synchronise à tous. Les planches PNG d'un bundle restent chez son propriétaire : les autres voient les grilles de pixels du sort.
- La run se termine quand tous les mages sont à terre. Un joueur peut rejoindre en cours de run. Départ de l'hôte : chacun repasse en solo.
- En ligne (`docker compose`, tâche #86) : le relais tourne dans son propre conteneur, à côté du serveur ; d'autres workers pourront héberger des parties plus tard.

## Décor des cartes
- Une carte par run (`crypt`, `cave`, `ruins`), tirée au début de la run ; le décor est placé une fois (graine), il ne change pas pendant la run.
- Planches PixelLab 128x128 (4x4 cases de 32x32), versionnées dans `assets/decor/<carte>.png`, dessinées au même facteur que les sorts (`SpellArt.PIXEL`). Rôle de chaque case : `Decor.MAPS` (`game/decor.gd`).
- Props non bloquants ; obstacles `wall` (les `bolt` s'y arrêtent) et `rock` (ils rebondissent) ; `crate` cassable par un `bolt`, lâche or et XP. Joueur et ennemis glissent autour des obstacles.
- Centre et bords (entrées des ennemis) dégagés, passage d'au moins 80 px entre deux obstacles.
- Lumières : halo pixel art en paliers, additif, qui vacille (pas de `PointLight2D`). Le décor est en `z_index = -1`, le sol doit être dessous.

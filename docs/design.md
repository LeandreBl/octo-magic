# Octo Magic — décisions de design

## Plateformes et technique
- PC, téléphone (Android/iOS) et navigateur, depuis un seul projet **Godot 4 / GDScript**.
- Jeu **hors ligne**. Connexion requise seulement pour : créer un parchemin, envoyer un score au classement, synchroniser le compte.
- Contrôles twin-stick : clavier/souris, manette, double joystick tactile.
- Backend minimal (tâche #86) : serveur NestJS en TypeScript (`backend/`, Prisma), login **Firebase**, profils et sorts en **Postgres**, forge (IA) derrière le login, export web du jeu, relais coop dans son conteneur ; le tout lancé par `docker compose`.

## Boucle de jeu
- Vue de dessus, vagues d'ennemis croissantes, boss toutes les N vagues.
- XP en run → level up → choix d'une amélioration.
- Mort permanente : la run est perdue, l'or est conservé.
- Or → boutique entre les runs (bâtons, robes, anneaux) + bonus permanents.
- Succès, déblocages, scores, classement (local d'abord).

## Monstres (tâche #140)
- Table de données `Run.ENEMIES` (`game/run.gd`) : stats, vague d'apparition et poids, IA, forme, sorts ; `game/enemy.gd` les joue.
- IA de déplacement : `chase` (fonce), `weave` (zigzague), `flank` (arrive par le côté), `kite` (garde sa distance et tourne autour).
- Sorts de monstres : `bolt`, `spread` (éventail), `ring` (360°), `nova` (onde télégraphiée), `fuse` (kamikaze), `puddle` (flaque de poison), `charge` (élan puis ruée), `blink` (téléportation), `heal` (soigne les alliés), `summon` ; `split` à la mort (slime).
- Zones au sol télégraphiées (contour qui se remplit) avant de faire mal : le joueur a toujours le temps d'esquiver.
- Vagues : mélange pondéré des types débloqués, tiré avec la vague pour graine (même plan chez tous les pairs). Trois boss en alternance toutes les 5 vagues : liche (`boss`), seigneur de guerre, mère des couvées.

## Personnage
- Le joueur est un **mage-poulpe** (la mascotte de l'icône), plus le boss (tâche #137) : vu de dessus (~90°), sprite PixelLab du corps (sans tentacules) qui tourne vers sa direction, idle, cast (un tentacule tient le bâton et l'abat vers la visée) et channeling (bâton tendu tant qu'un rayon ou un cône tourne) (`tools/make_octopus.py`, `assets/octo/`). Ses 8 tentacules sont animés sous le corps par de la physique (tâche #172, `game/tentacle.gd`) : chaîne Verlet ancrée au corps, pointe posée au sol qui fait un pas vers l'avant quand le corps s'en éloigne (deux groupes alternés, comme des pattes), ondulation latérale à l'arrêt ; forme par le code, texture PixelLab. Purement visuels : la hitbox reste le corps, chaque pair les simule localement.
- **Tous les sprites sont faits avec PixelLab** (personnages, ennemis, animations, icônes), pas dessinés en code. Pas de classes : chaque joueur personnalise son mage (apparence + équipement).
- Statistiques du mage en données (`game/stats.gd`, tâche #79) : PV, régénération de PV et de mana, mana, consommation de mana, vitesse, recharge, rayon de ramassage, armure, critique, dégâts, or, XP. Équipement, bonus permanents et augments « héros » des level-ups sont tous des bonus : base + bonus additifs, puis multiplicatifs (`"stat%"`, cumulés), puis bornes ; l'hôte les borne encore en coop. Critique : par lancer, ×2 dégâts.
- Sorts de base élémentaires (feu, glace, foudre, poison, arcane…), assets faits maison.

## Sorts
- Un seul sort équipé, au clic gauche (tâche #94).
- En run, l'or de la run achète (menu pause) **un sort secondaire** (clic droit / Espace / RB) et **un passif**, vides au départ et remis à zéro à chaque run (tâche #123, `Run.SHOP`) : anneau de feu (boules de feu à 360°) et bouclier (absorbe 40 dégâts, revient 8 s après s'être brisé).
- Améliorations par sort : vitesse du projectile (si pertinent), nombre de projectiles, coût en mana, dégâts, cadence, zone…
- Inspiration : sorts de base et augments de Solomon's Boneyard, **avec nos noms, nos valeurs et nos visuels** (on reprend la mécanique, pas le contenu).

## Parchemins (cœur du jeu)
- La boucle de jeu est **toujours hors ligne** (sauf la coop P2P). La forge a lieu **entre deux runs**, jamais pendant (décision tâche #75).
- En run, on trouve des parchemins vierges : ils sont gardés. À la fin de la run (dans le hub), le joueur en écrit un ou plusieurs d'un coup : un mot libre par parchemin, séparés par des espaces ou des virgules (tâche #85).
- Parser strict côté forge : lettres, `'` et `-` seulement, autant de mots que de parchemins (8 max) ; sinon refusé avant l'IA, parchemins intacts.
- Les parchemins n'acceptent que les **langues mortes** (latin, grec ancien, vieux norrois, sanskrit…) : un mot d'une langue vivante est annulé comme un mot sans sens. Le sort prend un nom dans cette langue, sa description reste en français (tâche #97).
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
- **Coopération** : les joueurs affrontent les vagues ensemble (8 max, hôte compris).
- Un joueur hôte fait tourner la partie (le même moteur), les autres sont clients : pas de code serveur de jeu. Solo = un hôte seul.
- Web et natif : **WebRTC en pair à pair** (tâche #93, remplace le relais WebSocket de #78) : les paquets du jeu vont directement entre joueurs en UDP (positions et visée en non fiable, sans blocage en tête de file). Le serveur ne fait que la mise en relation : salon à code court et signalisation sur `/play` (`backend/src/lobby/lobby.service.ts`), connexion requise. STUN public pour traverser les NAT, TURN (coturn, `docker-compose.yml`) quand le direct échoue. Côté Godot, `WebRTCMultiplayerPeer` (`game/net.gd`, intégré sur web, extension `webrtc-native` en natif) donne l'API haut niveau (RPC, `MultiplayerSpawner`, `MultiplayerSynchronizer`) ; les joueurs ne se connectent qu'à l'hôte, qui relaie entre eux.
- L'hôte fait autorité sur les ennemis, leurs tirs, les drops, les PV, le mana et les dégâts ; chaque joueur déplace et vise son mage lui-même (réactif malgré la latence). Les sorts lancés sont rejoués chez les autres pour l'affichage seulement. La carte (et sa graine) est envoyée à tous.
- Chaque joueur garde sa propre run (niveau, améliorations, sorts) ; les ennemis tués et les drops ramassés comptent pour tout le monde. Pas de pause au level-up en coop.
- Les sorts sont des données : un joueur envoie ses sorts en JSON à l'hôte, qui les nettoie (`Spell.sanitize`), calcule leur coût et les synchronise à tous. Les planches PNG d'un bundle restent chez son propriétaire : les autres voient les grilles de pixels du sort.
- La run se termine quand tous les mages sont à terre. Un joueur peut rejoindre en cours de run. Départ de l'hôte : chacun repasse en solo.
- En ligne (`docker compose`) : le salon est dans le serveur, coturn dans son propre conteneur (réseau de l'hôte, ports UDP).

## Carte
- La carte (`Arena.RECT`, `game/arena.gd`, environ 4x4 écrans ; une de `Arena.MAPS` par run, pour sa musique) est vide : seul son bord est dessiné. Les objets (décor, obstacles, caisses) viendront avec la tâche #92 ; les planches PixelLab de l'ancien décor restent dans `assets/decor/`.

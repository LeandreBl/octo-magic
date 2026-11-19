# Octo Magic — décisions de design

## Plateformes et technique
- PC, téléphone (Android/iOS) et navigateur, depuis un seul projet **Godot 4 / GDScript**.
- Jeu **hors ligne**. Connexion requise seulement pour : créer un parchemin, envoyer un score au classement, synchroniser le compte.
- Contrôles twin-stick : clavier/souris, manette, double joystick tactile.
- Backend minimal (tâche #86) : serveur NestJS en TypeScript (`backend/`, Prisma), login **Firebase**, profils et sorts en **Postgres**, forge (IA) derrière le login, export web du jeu, relais coop dans son conteneur ; le tout lancé par `docker compose`.

## Boucle de jeu
- Vue de dessus, vagues d'ennemis croissantes, boss toutes les N vagues.
- XP en run → level up (+100 PV et mana) ; les grimoires lâchés par les monstres donnent le choix d'un skill.
- Mort permanente : la run est perdue, l'or est conservé.
- Or → boutique entre les runs (bâtons, robes, anneaux) + bonus permanents.
- Succès, déblocages, scores, classement (local d'abord).

## Monstres (tâches #140, #174)
- DA : uniquement des morts-vivants et des créatures du cimetière (squelettes, archers, mages squelettes, zombies, diablotin, spectre ; boss : liche et boss monstres).
- Table de données `Run.ENEMIES` (`game/run.gd`) : stats, vague d'apparition et poids, IA, forme, sorts, tir, effet, variante ; `game/enemy.gd` les joue.
- IA de déplacement : `chase` (fonce), `weave` (zigzague), `still` (immobile : archers et mages).
- Sorts de monstres : `bolt`, `ring` (360°), `puddle` (flaque de poison ou brasier), `summon`, et ceux des boss monstres : `burst` (salves), `laser`, `teleport` (disparaît puis mord).
- Effets sur le mage (contact et tirs) : `poison` (dégâts par seconde), `freeze` (ralenti), `stun` (immobilisé). Le zombie putride laisse une flaque de poison à sa mort.
- Variantes tirées à l'apparition : casque (guerrier squelette), gantelets (chevalier squelette), bouclier magique (mages, plus de PV) ; sprite propre `<type>_<variante>`.
- Zones au sol télégraphiées (contour qui se remplit) avant de faire mal : le joueur a toujours le temps d'esquiver.
- Vagues : mélange pondéré des types débloqués, tiré avec la vague pour graine (même plan chez tous les pairs). Un boss toutes les 5 vagues (`Run.BOSSES`, tâche #296 ; leurs sorts reviennent 40 % plus tôt que leur `every`, `Run.BOSS_HASTE`, tâche #356) : liche (`boss`) en 5, puis les boss monstres, chacun ajoutant une attaque à celles du précédent : Héraut d'os en 10 (3 salves de 2 missiles), Seigneur du bûcher en 15 (+ boules de feu laissant un brasier qui brûle fort), Œil de la peste en 20 (+ laser vert, dégâts sur la durée), Gueule de la tombe en 25 (+ disparaît puis mord là où était le mage), Archidémon en 30 puis toutes les 5 vagues (+ ses boules de feu font éclore des diablotins de l'enfer, 2 de plus à chaque retour, qui lâchent or, orbes de vie/mana et parfois Quad Damage : dégâts x4 pendant 10 s). Vaincus, ils ajoutent 100/200/300/400/500 kills au score. Comme tous les ennemis, ils n'attaquent que s'ils sont à l'écran ; le gel les ralentit. Chevalier de la mort et abomination, qui ne sortaient plus, sont retirés (tâche #326).

## Personnage
- Le joueur est un **mage-poulpe** (la mascotte de l'icône), plus le boss (tâche #137) : vu de dessus (~90°), sprite PixelLab du corps (sans tentacules) qui tourne vers sa direction, idle, cast (un tentacule tient le bâton et l'abat vers la visée) et channeling (bâton tendu tant qu'un rayon ou un cône tourne) (`tools/make_octopus.py`, `assets/octo/`). Ses 8 tentacules sont animés sous le corps par de la physique (tâche #172, `game/tentacle.gd`) : bras musculaire plutôt que corde (tâche #225) : chaîne Verlet ancrée au corps qui garde sa longueur et résiste à la flexion (chaque articulation tirée vers une courbe cible, le bout plus enroulé que la base) ; lentement il rampe : la pointe tient le sol comme une ventouse, et quand le corps s'en éloigne elle lâche, se replie en se levant et se déroule sur un appui plus loin (deux groupes alternés, la flexion court de la base au bout)  ; il marche à toute vitesse, bras répartis autour du corps : plus il va vite, plus les pas s'accélèrent (tâche #430, au lieu de bras balayés vers l'arrière qui partaient tous à l'opposé du déplacement) ; à l'arrêt ils se tordent lentement, chacun à son rythme, et de temps en temps l'un se déplace ; chaque point est un corps qui se cogne aux murs de l'arène (rebond amorti) et est repoussé hors des ennemis proches (cercles), la pointe ne se pose jamais dedans (tâche #177) ; forme par le code, texture PixelLab dans le style des anciens tentacules (bout enroulé, contour noir), dessinée 1:1 sur des pixels entiers pour rester pixel art. Purement visuels : la hitbox reste le corps, chaque pair les simule localement.
- **Tous les sprites sont faits avec PixelLab** (personnages, ennemis, animations, icônes), pas dessinés en code. Pas de classes : chaque joueur personnalise son mage (apparence + équipement).
- Statistiques du mage en données (`game/stats.gd`, tâche #79) : PV, régénération de PV et de mana, mana, consommation de mana, vitesse, recharge, rayon de ramassage, armure, critique, dégâts, or, XP. Équipement, bonus permanents, perks et skills des grimoires sont tous des bonus : base + bonus additifs, puis multiplicatifs (`"stat%"`, cumulés), puis bornes ; l'hôte les borne encore en coop. Critique : par lancer, ×2 dégâts.
- Sorts de base élémentaires (feu, glace, foudre, poison, arcane…), assets faits maison.

## Sorts
- Un seul sort équipé, au clic gauche (tâche #94).
- **Rien ne s'achète pendant une run** : la boutique est entre les runs (tâche #195, remplace la boutique de run de #123).
- **Augments** (`Profile.AUGMENTS`, onglet de la boutique) : achetés une fois avec l'or du profil, gardés pour toutes les runs, chers (anneau de feu 1500, bouclier 1000). **3 emplacements** (`Profile.SLOTS`) : chaque run commence avec les augments placés, un actif (sort secondaire : clic droit / Espace / RB) au plus, le reste en passifs ou futurs bonus ; ça force à choisir. Anneau de feu (boules de feu à 360°), bouclier (absorbe 40 dégâts, revient 8 s après s'être brisé).
- **Perks** (tâche #295, d'après la liste du propriétaire, adaptée à une seule carte) : augments passifs du même onglet. Bonus de stats (vie +25, mana +50, vitesse +10 %, -15 % de coût, -10 % de recharge, ramassage x4, +50 % d'or, -10 % de poison, orbes x2, grimoires et parchemins x2, Extrême : dégâts infligés et subis x2), règles de run (4 cartes par grimoire ; 1 ou 2 grimoires rouges et bleus ouverts au départ), et côté mage (3 fioles bues seules sous 30 % des PV, explosion de feu à la mort, flèches vers grimoires et parchemins). Bonus permanent « En forme » : +1 emplacement, deux fois (2500 puis 20000). Écartés : anneaux trouvés en run (pas d'anneaux en run), sorts secondaires multiples (déjà les emplacements), acheter son amélioration (rien ne s'achète en run), autres cimetières (une carte), boss (déjà là).
- **Skills en run** (tâche #308, `Upgrades.LIST`) : chaque grimoire propose 3 skills de sa couleur (rouge : héros, bleu : sort) ; prendre un skill monte son niveau (Skill I, II, III…) jusqu'à son max, un skill au max n'est plus proposé. Chaque skill est un bonus de stats par niveau. Plus de raretés ni d'améliorations qui modifient le sort (projectiles, zone, perforation…). Les skills, un par tâche (#309 à #320) : coût en mana -15 %/niv (niv 11), régén de mana +35 %/niv (9), un choix de plus par grimoire (une fois), cadence +10 %/niv (9), vie +25/niv (4), mana +50/niv (4), canaliser à l'arrêt pour un mana x4 (une fois), résistance au poison et au feu +10 %/niv (9), vitesse +10 %/niv (8), ramassage +30 %/niv (5), dégâts +25 %/niv (9).
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
- La carte (`game/arena.gd`) est un **cimetière** peint en deux calques fournis par le propriétaire (1536x1024) : le sol (`assets/maps/graveyard/ground.png`) et ce qui est en l'air (`above.png` : arbres, toits), dessiné par-dessus les persos ; seule sa partie **dans le halo** du mage local (`Arena.SEE`, 140 px) passe en transparence moyenne (`Arena.FADED`, shader), et seulement quand le mage marche sous un élément (`Arena.under` : son milieu ou son bord, `Arena.BODY`, sur un pixel du calque ; le halo s'allume et s'éteint en fondu). Affichés x1,5 (`Arena.SCALE` : la pieuvre fait à peu près une tombe), caméra zoomée x4/3 sur le mage (un pixel de la carte = 2 pixels d'écran). Musique : une piste de `Sfx.TRACKS` au début du run (choisie par l'hôte), puis les autres au hasard.
- Ses zones sont posées à la main dans `map.json` (en pixels de l'image) avec l'éditeur `python3 tools/map_editor.py graveyard` (navigateur, http://localhost:8765, avec un personnage de test qui marche comme le mage et le calque du dessus) : **polygones** bloquants (chapelle, mausolées, rotonde, murs et grilles, hors-limites), **cercles** bloquants (pied des tombes, troncs, statue, lanternes), sorties de monstres et départ des mages (`start`). Mage et monstres glissent autour (`Arena.slide`). Les monstres sortent des tombes ouvertes (`spawns`), **jamais dans la vue d'un joueur** (`Arena.spawn_point` : écran de chaque mage, prévu jusqu'au 21:9 et au 4:3) : la tombe cachée la plus proche d'un mage, sinon un endroit libre hors de toutes les vues.
- ~~Cartes générées~~ (tâche #92, voir l'historique git) : image agrandie par outpainting (coutures, kaléidoscope), pâtés pixen et routes repeintes par inpainting (coutures), tuiles + objets PixelLab placés par programme (juste, mais laid : vues incohérentes, composition mécanique).

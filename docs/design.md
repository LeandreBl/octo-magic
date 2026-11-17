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
- Succès, déblocages, scores, classement en ligne.

## Personnage
- Pas de classes : chaque joueur personnalise son mage (apparence + équipement).
- Sorts de base élémentaires (feu, glace, foudre, poison, arcane…), assets faits maison.

## Sorts
- Emplacements : sort principal, sort secondaire, ultime.
- Améliorations par sort : vitesse du projectile (si pertinent), nombre de projectiles, coût en mana, dégâts, cadence, zone…
- Inspiration : sorts de base et augments de Solomon's Boneyard, **avec nos noms, nos valeurs et nos visuels** (on reprend la mécanique, pas le contenu).

## Parchemins (cœur du jeu)
- En run, on trouve un parchemin vierge ; le joueur y écrit un mot libre.
- Le mot part au backend (modération, puis IA) qui renvoie un **JSON de sort** composé de briques connues du moteur : forme, trajectoire, élément, effets, visuel.
- Le moteur calcule un **budget de puissance** : l'IA décrit, le moteur équilibre.
- Temps d'attente façon Clash of Clans pendant la génération.
- Le sort est lié au compte, stocké en local, jouable hors ligne.
- **Classement** : le serveur signe chaque sort généré ; un score n'est accepté que si ses sorts ont une signature valide.

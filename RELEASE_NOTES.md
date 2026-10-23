# notchnotch : nouveautés depuis v1.4.0

Cette version suit Hermes jusqu'à la **v0.22.5** (sortie le 22 octobre 2026). Son nouveau gateway changeait la façon de répondre aux approbations et d'identifier les conversations : sans cette mise à jour, « Autoriser » et « Refuser » ne répondaient plus et l'historique perdait les nouvelles conversations. Les anciennes versions d'Hermes (dès la v0.11) continuent de marcher.

## Hermes demande avant d'agir

Quand ton agent veut lancer une commande risquée (supprimer des fichiers, toucher au système), une carte apparaît dans sa réponse : **Autoriser** une fois, ou **Refuser**. Notch fermé, un toast te prévient qu'il attend. Le mode se règle dans Réglages : demander (manuel), laisser Hermes juger (intelligent) ou désactivé.

## Un chat plus vivant, et un vrai Stop

- Sur Hermes v0.21.6 et plus, le chat passe par l'API en direct d'Hermes : tu vois son raisonnement et une ligne d'état pendant qu'il travaille.
- **Stop** arrête vraiment l'agent, même au milieu d'une commande. Avant, fermer la réponse laissait la commande aller au bout.
- Une vraie erreur du fournisseur (crédit épuisé, hors ligne) s'affiche comme une erreur, plus comme une réponse.

## Le modèle de cette conversation

Le menu du modèle, dans la barre du notch, liste les fournisseurs que tu as connectés dans Hermes et change le modèle **pour cette conversation seulement**. Le modèle par défaut reste dans Réglages. La barre tient sur une ligne même avec un nom de modèle long, et la jauge de contexte affiche le nombre de jetons au survol.

## La palette `/`

Tape `/` dans le champ : les commandes de notchnotch (`/new`, `/model`, `/sessions`, `/stop`) avec leur description, puis tes skills. Flèches, Tab, Entrée, Échap. Les commandes d'Hermes qui ne marchent pas par l'API (`/goal`, `/loop`…) ne partent plus au modèle, qui faisait semblant de les exécuter : notchnotch te dit où elles marchent. Une faute de frappe proche (`/models`) te propose la bonne commande.

## Missions

- Pause, reprise et changement d'horaire directement dans l'onglet Missions.
- Un toast rouge au premier échec d'une série, avec la raison ; une tape ouvre Missions.
- Le bandeau de coût n'affiche plus un faux « 0,00 $ » quand Hermes ne connaît pas le prix : il dit combien de sessions sont sans tarif.

## Un onboarding en 4 écrans

Bienvenue, Installation, Connexion, Prêt. Hermes s'installe étape par étape, sur sa dernière version stable. La connexion se fait en un clic avec OpenRouter (un modèle gratuit qui sait utiliser des outils est choisi pour toi), ou avec ta propre clé OpenRouter, OpenAI, Anthropic ou MiniMax. Contrôle du Mac passe dans les Réglages.

## Réglages

- **Contrôle du Mac** affiche le vrai état des autorisations, lu chez Hermes, et un bouton « Autoriser » qui les demande en une fois.
- **Mémoire** : le sélecteur liste les fournisseurs de mémoire qu'Hermes trouve vraiment, intégrés ou installés depuis le catalogue.
- **Confidentialité OpenRouter** : une ligne qui mène à tes réglages de confidentialité chez OpenRouter.
- **Clés** : `~/.hermes/.env` est créé lisible par toi seul, avec un lien vers les coffres 1Password et Bitwarden pris en charge par Hermes.

## Petits correctifs

- Les infobulles s'affichent enfin dans le notch : celles de macOS n'y apparaissaient jamais.
- Modifier ou supprimer un souvenir marche avec la mémoire d'Hermes v0.22.
- Plus de fenêtre Réglages vide au lancement.
- L'accent de l'interface est blanc.

## Pour mettre à jour

Sparkle te propose la mise à jour. Pour profiter de tout, mets aussi Hermes à jour (`hermes update`) ; notchnotch reste compatible avec ta version actuelle.

Bypass Gatekeeper au premier lancement (clic droit → Ouvrir → Ouvrir) : notchnotch n'est pas notarisé par Apple.

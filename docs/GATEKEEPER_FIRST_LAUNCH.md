# Première ouverture de notchnotch

## Pourquoi macOS me dit que l'app est bloquée ?

notchnotch est signée localement (« ad-hoc »), pas avec un certificat
Apple Developer payant (99 $/an). Du coup, la première fois que tu
ouvres l'app — et chaque fois que tu installes une mise à jour — macOS
affiche un message du genre :

> « notchnotch » ne peut pas être ouverte parce que Apple ne peut pas
> vérifier qu'elle ne contient pas de logiciel malveillant.

Ce message ne veut **pas** dire que l'app est dangereuse. Il veut dire
que macOS n'a pas encore vu de certificat Apple sur ce binaire. Le code
source est public sur [GitHub](https://github.com/KikinaStudio/NotchNotch),
tu peux le vérifier toi-même.

## Comment l'autoriser

### Méthode 1 — clic droit (la plus rapide)

1. Ouvre le dossier **Applications** dans le Finder.
2. **Clic droit** (ou Ctrl+clic) sur `notchnotch.app`.
3. Choisis **Ouvrir** dans le menu.
4. Une boîte de dialogue apparaît avec un bouton **Ouvrir** — clique
   dessus.

C'est tout. La prochaine fois (jusqu'à la prochaine mise à jour), tu
peux double-cliquer normalement.

### Méthode 2 — via les Réglages Système

Si la méthode 1 ne marche pas (sur certaines versions de macOS le clic
droit ne suffit plus) :

1. Essaie d'ouvrir notchnotch normalement. macOS te dit que c'est
   bloqué — ferme la boîte de dialogue.
2. Ouvre **Réglages Système** → **Confidentialité et sécurité**.
3. Descends jusqu'à la section **Sécurité**. Tu verras :
   *« notchnotch » a été bloquée pour protéger votre Mac.*
4. Clique **Ouvrir quand même** à côté.
5. Ré-ouvre notchnotch — confirme avec **Ouvrir** dans la nouvelle
   boîte de dialogue.

## Et pour les mises à jour ?

Chaque nouvelle version refait le warning, parce que macOS traite chaque
binaire ad-hoc-signé comme un nouveau logiciel inconnu. La même méthode
s'applique. notchnotch t'affiche d'ailleurs un rappel automatique après
chaque mise à jour avec un bouton « Ouvrir Réglages » qui t'amène
directement au bon panneau.

## Vérifier que l'app n'a pas été altérée

Si tu veux vérifier que le binaire que tu as téléchargé correspond bien
à celui publié sur GitHub :

```sh
shasum -a 256 /Applications/notchnotch.app/Contents/MacOS/notchnotch
```

Compare le résultat au hash publié dans les notes de la
[release GitHub](https://github.com/KikinaStudio/NotchNotch/releases) de
ta version.

## Et si je veux une app signée Apple ?

C'est sur la roadmap, mais ça dépend d'un compte Apple Developer payant.
En attendant, le warning Gatekeeper est le compromis qu'on accepte pour
distribuer notchnotch gratuitement.

# notchnotch v1.3.2

## Hotfix release (DEUXIÈME tentative)

Si tu as v1.3.0 ou v1.3.1 qui crashe au démarrage, **c'est cette version-là qu'il te faut**.

### Le vrai problème

Sur macOS Tahoe avec hardened runtime, **library validation** est enforcée par défaut. Un framework embedded (Sparkle) doit avoir le même Team ID que l'app hôte… ou alors l'entitlement `com.apple.security.cs.disable-library-validation` doit être présent.

notchnotch est ad-hoc-signé (TeamID vide), Sparkle aussi (après mon fix v1.3.1 qui re-signait inside-out). Mais **TeamID vide n'est PAS traité comme "même TeamID"** par dyld sur Tahoe — c'est traité comme "pas de TeamID = échec library validation". D'où le crash `mapping process and mapped file (non-platform) have different Team IDs` même quand les deux ont `TeamIdentifier=not set`.

v1.3.1 corrigeait le bon inside-out signing mais ratait la racine. v1.3.2 ajoute l'entitlement.

### Le fix

`BoaNotch/BoaNotch.entitlements` gagne `com.apple.security.cs.disable-library-validation`. C'est la recette standard Sparkle pour les distros non-notarized. La Sandbox reste off (off depuis le début), le hardened runtime reste on, seule la library validation est relâchée.

Vérifié en local : avec l'entitlement, l'app lance sans crash. Sans, crash dyld immédiat.

### Pour mettre à jour

- **Depuis v1.2.1** : Sparkle te proposera v1.3.2 automatiquement
- **Depuis v1.3.0 ou v1.3.1 (qui crashent)** : tu dois **re-télécharger le DMG manuellement** depuis [GitHub Releases](https://github.com/KikinaStudio/NotchNotch/releases/tag/v1.3.2). Sparkle ne peut pas tourner sur une app qui ne lance pas.

### Le reste

Tout le contenu de v1.3.0/v1.3.1 est inclus : Contrôle du Mac (opt-in), trois onglets Memory/Tools/Missions, timeline unifiée du chat, Liquid Glass, SF Symbols 7, Hermes 0.13 (SSE retry, FR locale, fix MiniMax), refine wand sur routines locales, toasts par couleur sémantique, empty-state carousel, 11 providers LLM, sélecteur de memory provider.

Bypass Gatekeeper au premier launch (right-click → Open → Open) — notchnotch n'est pas notarized par Apple.

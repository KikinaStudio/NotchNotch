# notchnotch v1.3.1

## Hotfix release

Si tu as téléchargé v1.3.0 et que l'app crashe au démarrage (rien ne s'affiche après le double-clic), c'est pour toi.

### Le problème

v1.3.0 shippait Sparkle.framework avec sa signature d'origine (Sparkle developers). Sur macOS Tahoe avec hardened runtime, dyld refuse de charger un framework embedded dont le TeamID diffère de l'app hôte. notchnotch étant ad-hoc-signé (TeamID vide), Sparkle (TeamID Sparkle) → mismatch → crash 3 secondes après le launch.

`codesign --deep` était censé re-signer Sparkle avec notre identité ad-hoc mais skippait les binaires déjà valablement signés. Bug latent depuis l'intro de Sparkle (v1.2.x) qui se manifestait surtout sur Tahoe fraîche.

### Le fix

`scripts/release.sh` re-signe maintenant Sparkle.framework **inside-out explicitement** avant le sign outer : XPCServices/Downloader.xpc, XPCServices/Installer.xpc, Updater.app, Autoupdate, le dylib Sparkle, puis le bundle complet. Tous prennent la même identité ad-hoc que notchnotch.app. Plus de TeamID mismatch.

### Pour mettre à jour

Si tu avais v1.2.1 qui marche, Sparkle te proposera v1.3.1 automatiquement.

Si tu as v1.3.0 (qui crashe), **tu dois re-télécharger manuellement** depuis [GitHub Releases](https://github.com/KikinaStudio/NotchNotch/releases/tag/v1.3.1) — l'app v1.3.0 ne peut pas démarrer Sparkle, donc l'auto-update ne fonctionne pas pour cette version.

### Tout le reste de v1.3.0

Les nouveautés v1.3.0 sont incluses ici : Contrôle du Mac (opt-in), trois onglets Memory/Tools/Missions, timeline unifiée du chat, Liquid Glass, SF Symbols 7, Hermes 0.13 (SSE retry, FR locale, fix MiniMax), refine wand sur routines locales, toasts par couleur sémantique, empty-state carousel, 11 providers LLM, sélecteur de memory provider.

### Pour mettre à jour (depuis v1.2.1)

notchnotch te proposera la mise à jour automatiquement au prochain lancement. À chaque mise à jour, refais le bypass Gatekeeper au premier launch (right-click → Open → Open) — l'app n'est pas (encore) notarized par Apple.

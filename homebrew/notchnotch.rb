# Homebrew Cask formula for notchnotch
# To use: create a repo KikinaStudio/homebrew-tap with this file at Casks/notchnotch.rb
# Install: brew install --cask KikinaStudio/tap/notchnotch --no-quarantine

cask "notchnotch" do
  version "0.8.0"
  sha256 "" # fill with: shasum -a 256 notchnotch-v0.8.0.dmg

  url "https://github.com/KikinaStudio/NotchNotch/releases/download/v#{version}/notchnotch-v#{version}.dmg"
  name "notchnotch"
  desc "AI agent in your MacBook notch — installs and runs Hermes, no terminal needed"
  homepage "https://github.com/KikinaStudio/NotchNotch"

  depends_on macos: ">= :sonoma"

  app "notchnotch.app"

  zap trash: [
    "~/Library/Preferences/com.leon.boanotch.plist",
    "~/Library/Preferences/BoaNotch.plist",
  ]
end

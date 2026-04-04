# Homebrew Cask formula for BoaNotch
# To use: create a repo KikinaStudio/homebrew-tap with this file at Casks/boanotch.rb
# Install: brew install --cask KikinaStudio/tap/boanotch --no-quarantine

cask "boanotch" do
  version "0.6.0"
  sha256 "" # TODO: fill with: shasum -a 256 BoaNotch-v0.6.0.dmg

  url "https://github.com/KikinaStudio/BoaNotch/releases/download/v#{version}/BoaNotch-v#{version}.dmg"
  name "BoaNotch"
  desc "AI chat in your MacBook notch — native Hermes agent client"
  homepage "https://github.com/KikinaStudio/BoaNotch"

  depends_on macos: ">= :sonoma"

  app "BoaNotch.app"

  zap trash: [
    "~/Library/Preferences/com.leon.boanotch.plist",
  ]
end

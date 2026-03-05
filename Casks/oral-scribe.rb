cask "oral-scribe" do
  version "1.0.0"
  sha256 "fdb78cd4b3f023800343d3c2e04cc6db4e44212d7a50c74295c2aadba3216376"

  url "https://github.com/neverprepared/oral-scribe/releases/download/v#{version}/OralScribe.dmg"
  name "Oral Scribe"
  desc "Menu bar dictation app — press a hotkey, speak, get text"
  homepage "https://github.com/neverprepared/oral-scribe"

  depends_on macos: ">= :ventura"

  app "OralScribe.app"

  zap trash: [
    "~/Library/Preferences/com.oralscribe.app.plist",
    "~/Library/Application Support/OralScribe",
    "~/Library/Saved Application State/com.oralscribe.app.savedState",
  ]
end

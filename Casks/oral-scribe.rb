cask "oral-scribe" do
  version "1.4.0"
  sha256 "f40f80c192e896d53af7a369626dab34f99d088c3658957845ee15db5c7c3dda"

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

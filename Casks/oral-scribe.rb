cask "oral-scribe" do
  version "1.3.1"
  sha256 "a8937c3baf5734b47ab47f19c5c46181ec764eee31ac9c39c9d08343c2ee4a5f"

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

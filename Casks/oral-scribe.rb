cask "oral-scribe" do
  version "1.3.5"
  sha256 "3a92a7e5a95b7a465cc56f0161512458bbb85bcbd4cd048d70ed1b13db65ec57"

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

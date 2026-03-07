cask "oral-scribe" do
  version "1.3.4"
  sha256 "1fa475279d3358a6bcf236ae36789a3109db5aeb54a9ea1e296284703154a860"

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

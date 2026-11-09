#!/usr/bin/env bash
# Cut a release: set the version, build the combined archive, tag, push, publish on GitHub,
# and update the Homebrew cask in the tap checkout.
#
# Usage: scripts/release.sh <version> <notes-file> [tap-dir]
#   tap-dir defaults to ../homebrew-defectdash (a checkout of Arawn-Davies/homebrew-defectdash)
set -euo pipefail

version=${1:?version, e.g. 0.0.4}
notes=${2:?release notes markdown file}
tap=${3:-../homebrew-defectdash}
cd "$(dirname "$0")/.."

plist=Sources/DefectDash/Resources/Info.plist
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $version" "$plist"

make dist VERSION="$version"
zip="build/DefectDash-$version-macos-arm64.zip"
sha=$(shasum -a 256 "$zip" | cut -d' ' -f1)

if ! git diff --quiet -- "$plist"; then
  git add "$plist"
  git commit -q -m "Version $version"
fi
git tag -s "v$version" -m "DefectDash $version"
git push origin main "v$version"
gh release create "v$version" "$zip" --title "DefectDash $version" --latest --notes-file "$notes"

# Homebrew cask
if [ -d "$tap/.git" ]; then
  cat > "$tap/Casks/defectdash.rb" <<RUBY
cask "defectdash" do
  version "$version"
  sha256 "$sha"

  url "https://github.com/Arawn-Davies/DefectDash/releases/download/v#{version}/DefectDash-#{version}-macos-arm64.zip"
  name "DefectDash"
  desc "Ranked Asana defects joined with your local git worktrees: macOS app and terminal UI"
  homepage "https://github.com/Arawn-Davies/DefectDash"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: ">= :sequoia"
  depends_on arch: :arm64

  app "DefectDash.app"
  binary "defectdash"

  # Both binaries are ad-hoc signed and not notarized; without this Gatekeeper refuses to run them.
  # The app lives in appdir; the terminal binary stays in the Caskroom and is symlinked into bin.
  postflight do
    system_command "/usr/bin/xattr",
                   args: ["-dr", "com.apple.quarantine", "#{appdir}/DefectDash.app"],
                   sudo: false
    system_command "/usr/bin/xattr",
                   args: ["-d", "com.apple.quarantine", "#{staged_path}/defectdash"],
                   sudo: false,
                   must_succeed: false
  end

  zap trash: "~/Library/Preferences/io.github.arawn-davies.defectdash.plist"
end
RUBY
  git -C "$tap" add Casks/defectdash.rb
  git -C "$tap" commit -q -m "defectdash $version"
  git -C "$tap" push origin HEAD
  echo "cask updated: $tap/Casks/defectdash.rb"
else
  echo "warning: tap checkout not found at $tap; cask not updated (sha256 $sha)" >&2
fi
echo "released v$version  sha256 $sha"

cask "sloppy" do
  version "1.2.4"
  sha256 "57dee4d5b955c76cc4d3f4b52045593ace851f9a1dde967cb5ce692297bddbc4"

  url "https://github.com/TeamSloppy/Sloppy/releases/download/v1.2.4/Sloppy-macos-arm64.tar.gz"
  name "Sloppy"
  desc "Agent runtime and dashboard for Sloppy"
  homepage "https://github.com/TeamSloppy/Sloppy"

  binary "bin/sloppy"

  artifact "share/sloppy/dashboard", target: "#{Dir.home}/.local/share/sloppy/dashboard"
end

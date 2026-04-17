cask "sloppy" do
  version "1.1.2"
  sha256 "1281981d0cc45c10ee0017a9f787b91568687a8febbc8e66ef353282256b61b0"

  url "https://github.com/TeamSloppy/Sloppy/releases/download/v1.1.2/Sloppy-macos-arm64.tar.gz"
  name "Sloppy"
  desc "Agent runtime and dashboard for Sloppy"
  homepage "https://github.com/TeamSloppy/Sloppy"

  binary "bin/sloppy"
  binary "bin/SloppyNode"

  artifact "share/sloppy/dashboard", target: "#{Dir.home}/.local/share/sloppy/dashboard"
end

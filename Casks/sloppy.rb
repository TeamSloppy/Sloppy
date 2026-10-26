cask "sloppy" do
  version "2.5.1"
  sha256 "e18eebb2ea1a81d4be7a4e63505036991423ccbcbe50d948611aded14cecb426"

  url "https://github.com/TeamSloppy/Sloppy/releases/download/v2.5.1/Sloppy-macos-arm64.tar.gz"
  name "Sloppy"
  desc "Agent runtime and dashboard for Sloppy"
  homepage "https://github.com/TeamSloppy/Sloppy"

  binary "bin/sloppy"

  artifact "share/sloppy/dashboard", target: "#{Dir.home}/.local/share/sloppy/dashboard"
end

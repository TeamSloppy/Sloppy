cask "sloppy" do
  version "1.2.2"
  sha256 "6a8b1cfe888a51bdece20205ea9826cd4357cfbb37012eb240078ff1597ea229"

  url "https://github.com/TeamSloppy/Sloppy/releases/download/v1.2.2/Sloppy-macos-arm64.tar.gz"
  name "Sloppy"
  desc "Agent runtime and dashboard for Sloppy"
  homepage "https://github.com/TeamSloppy/Sloppy"

  binary "bin/sloppy"

  artifact "share/sloppy/dashboard", target: "#{Dir.home}/.local/share/sloppy/dashboard"
end

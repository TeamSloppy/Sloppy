cask "sloppy" do
  version "2.5.0"
  sha256 "770a309f298aea9b552a7776429255eb8cef096bd51510e9267bc62997c71d59"

  url "https://github.com/TeamSloppy/Sloppy/releases/download/v2.5.0/Sloppy-macos-arm64.tar.gz"
  name "Sloppy"
  desc "Agent runtime and dashboard for Sloppy"
  homepage "https://github.com/TeamSloppy/Sloppy"

  binary "bin/sloppy"

  artifact "share/sloppy/dashboard", target: "#{Dir.home}/.local/share/sloppy/dashboard"
end

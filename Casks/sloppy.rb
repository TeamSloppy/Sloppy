cask "sloppy" do
  version "1.2.0"
  sha256 "55934de1e40aa95b0fc4021dfe7773a84c22322b2263af43ec1ecb779d2f3dec"

  url "https://github.com/TeamSloppy/Sloppy/releases/download/v1.2.0/Sloppy-macos-arm64.tar.gz"
  name "Sloppy"
  desc "Agent runtime and dashboard for Sloppy"
  homepage "https://github.com/TeamSloppy/Sloppy"

  binary "bin/sloppy"

  artifact "share/sloppy/dashboard", target: "#{Dir.home}/.local/share/sloppy/dashboard"
end

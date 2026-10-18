cask "sloppy-node" do
  version "2.5.0"
  sha256 "0377134f781c113f5a1982ed4ff393f3a4696e3a5f3d25b9082bfb453bc432f3"

  url "https://github.com/TeamSloppy/Sloppy/releases/download/v2.5.0/SloppyNode-macos-arm64.tar.gz"
  name "SloppyNode"
  desc "Local computer-control executor for Sloppy"
  homepage "https://github.com/TeamSloppy/Sloppy"

  binary "bin/sloppy-node"
end

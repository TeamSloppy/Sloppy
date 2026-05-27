cask "sloppy-node" do
  version "1.2.0"
  sha256 "17b43d1e95d12d447d279abc415919c92a3b4e7cb82aae4005e30e1377833370"

  url "https://github.com/TeamSloppy/Sloppy/releases/download/v1.2.0/SloppyNode-macos-arm64.tar.gz"
  name "SloppyNode"
  desc "Local computer-control executor for Sloppy"
  homepage "https://github.com/TeamSloppy/Sloppy"

  binary "bin/sloppy-node"
end

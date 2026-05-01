cask "sloppy-node" do
  version "1.1.3"
  sha256 "bd575b548aa46859ede1881085c7d598db4e29218b3bb1bc022f7d5d4f69ce79"

  url "https://github.com/TeamSloppy/Sloppy/releases/download/v1.1.3/Sloppy-macos-arm64.tar.gz"
  name "SloppyNode"
  desc "Local computer-control executor for Sloppy"
  homepage "https://github.com/TeamSloppy/Sloppy"

  binary "bin/SloppyNode", target: "sloppy-node"
end

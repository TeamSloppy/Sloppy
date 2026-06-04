cask "sloppy-node" do
  version "1.2.2"
  sha256 "ca26ac939cb91270421d2d681b6a9bdb47766333452559ec54e7420a1bf6ad13"

  url "https://github.com/TeamSloppy/Sloppy/releases/download/v1.2.2/SloppyNode-macos-arm64.tar.gz"
  name "SloppyNode"
  desc "Local computer-control executor for Sloppy"
  homepage "https://github.com/TeamSloppy/Sloppy"

  binary "bin/sloppy-node"
end

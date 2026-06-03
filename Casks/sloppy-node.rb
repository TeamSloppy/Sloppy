cask "sloppy-node" do
  version "1.2.1"
  sha256 "17b7a44822fac22f5adbd96248ad7c79b282ef271ced6ae87304f0cd991399f5"

  url "https://github.com/TeamSloppy/Sloppy/releases/download/v1.2.1/SloppyNode-macos-arm64.tar.gz"
  name "SloppyNode"
  desc "Local computer-control executor for Sloppy"
  homepage "https://github.com/TeamSloppy/Sloppy"

  binary "bin/sloppy-node"
end

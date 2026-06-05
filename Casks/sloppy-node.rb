cask "sloppy-node" do
  version "1.2.4"
  sha256 "89e9eb9c06b56ff90517f4a69032578958e57b7d987e1a7c54b744d9979f879b"

  url "https://github.com/TeamSloppy/Sloppy/releases/download/v1.2.4/SloppyNode-macos-arm64.tar.gz"
  name "SloppyNode"
  desc "Local computer-control executor for Sloppy"
  homepage "https://github.com/TeamSloppy/Sloppy"

  binary "bin/sloppy-node"
end

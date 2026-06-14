cask "sloppy-node" do
  version "1.3.0"
  sha256 "7e5f923e3ee527274c3e8f9c1226a2ad8388aa8418811cea6e31686daad2930f"

  url "https://github.com/TeamSloppy/Sloppy/releases/download/v1.3.0/SloppyNode-macos-arm64.tar.gz"
  name "SloppyNode"
  desc "Local computer-control executor for Sloppy"
  homepage "https://github.com/TeamSloppy/Sloppy"

  binary "bin/sloppy-node"
end

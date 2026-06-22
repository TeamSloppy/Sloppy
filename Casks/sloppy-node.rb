cask "sloppy-node" do
  version "1.3.2"
  sha256 "1bd61631739bc091c2fcb67fc39a14444af361e60488cd179a08ff01119e5f31"

  url "https://github.com/TeamSloppy/Sloppy/releases/download/v1.3.2/SloppyNode-macos-arm64.tar.gz"
  name "SloppyNode"
  desc "Local computer-control executor for Sloppy"
  homepage "https://github.com/TeamSloppy/Sloppy"

  binary "bin/sloppy-node"
end

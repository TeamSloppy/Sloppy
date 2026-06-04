cask "sloppy-node" do
  version "1.2.3"
  sha256 "963c98249122d11430c50f07098bca3d57e2a4b42cb1b9e3a27d36be427e0794"

  url "https://github.com/TeamSloppy/Sloppy/releases/download/v1.2.3/SloppyNode-macos-arm64.tar.gz"
  name "SloppyNode"
  desc "Local computer-control executor for Sloppy"
  homepage "https://github.com/TeamSloppy/Sloppy"

  binary "bin/sloppy-node"
end

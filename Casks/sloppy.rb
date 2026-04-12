cask "sloppy" do
  version "1.0.0"
  sha256 "853567453612089e80f946151edbf56cec71c2c018e12725861631a486562419"

  url "https://github.com/TeamSloppy/Sloppy/releases/download/v1.0.0/Sloppy-macos-arm64.tar.gz"
  name "Sloppy"
  desc "Agent runtime and dashboard for Sloppy"
  homepage "https://github.com/TeamSloppy/Sloppy"

  binary "bin/sloppy"
  binary "bin/SloppyNode"

  artifact "share/sloppy/dashboard", target: "#{Dir.home}/.local/share/sloppy/dashboard"
end

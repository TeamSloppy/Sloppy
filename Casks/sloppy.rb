cask "sloppy" do
  version "1.2.1"
  sha256 "2729671fd5c9d0967f77c5ecfec6363892f8666cf11dc512b38476937a64fc6c"

  url "https://github.com/TeamSloppy/Sloppy/releases/download/v1.2.1/Sloppy-macos-arm64.tar.gz"
  name "Sloppy"
  desc "Agent runtime and dashboard for Sloppy"
  homepage "https://github.com/TeamSloppy/Sloppy"

  binary "bin/sloppy"

  artifact "share/sloppy/dashboard", target: "#{Dir.home}/.local/share/sloppy/dashboard"
end

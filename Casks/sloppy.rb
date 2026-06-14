cask "sloppy" do
  version "1.3.0"
  sha256 "13fe7b337e073b270a504944cb1b4135545376e3641aef1cbcbae54f8e31dd14"

  url "https://github.com/TeamSloppy/Sloppy/releases/download/v1.3.0/Sloppy-macos-arm64.tar.gz"
  name "Sloppy"
  desc "Agent runtime and dashboard for Sloppy"
  homepage "https://github.com/TeamSloppy/Sloppy"

  binary "bin/sloppy"

  artifact "share/sloppy/dashboard", target: "#{Dir.home}/.local/share/sloppy/dashboard"
end

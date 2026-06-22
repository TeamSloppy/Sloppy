cask "sloppy" do
  version "1.3.2"
  sha256 "a6ed01e34aaa41cb70571895a942fc377eeb6463c48809633b36e27447bbbcad"

  url "https://github.com/TeamSloppy/Sloppy/releases/download/v1.3.2/Sloppy-macos-arm64.tar.gz"
  name "Sloppy"
  desc "Agent runtime and dashboard for Sloppy"
  homepage "https://github.com/TeamSloppy/Sloppy"

  binary "bin/sloppy"

  artifact "share/sloppy/dashboard", target: "#{Dir.home}/.local/share/sloppy/dashboard"
end

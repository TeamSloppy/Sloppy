cask "sloppy" do
  version "1.2.3"
  sha256 "5f854b99ce7a0e5f695cbe88be0e8149c3ae6643de65d931b83a6b576e37dbdc"

  url "https://github.com/TeamSloppy/Sloppy/releases/download/v1.2.3/Sloppy-macos-arm64.tar.gz"
  name "Sloppy"
  desc "Agent runtime and dashboard for Sloppy"
  homepage "https://github.com/TeamSloppy/Sloppy"

  binary "bin/sloppy"

  artifact "share/sloppy/dashboard", target: "#{Dir.home}/.local/share/sloppy/dashboard"
end

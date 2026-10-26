class Sloppy < Formula
  desc "Agent runtime and dashboard for Sloppy"
  homepage "https://github.com/TeamSloppy/Sloppy"
  version "2.5.1"
  url "https://github.com/TeamSloppy/Sloppy/releases/download/v2.5.1/Sloppy-linux-x86_64.tar.gz"
  sha256 "b7ec735f365074e113c025f44ddaee48156ed0f2ba5c67539a062309606f8357"
  license "AGPL-3.0-only"

  def install
    bin.install Dir["bin/*"]
    (share/"sloppy").install Dir["share/sloppy/*"]
  end

  test do
    system "#{bin}/sloppy", "--version"
  end
end

class Sloppy < Formula
  desc "Agent runtime and dashboard for Sloppy"
  homepage "https://github.com/TeamSloppy/Sloppy"
  version "1.3.0"
  url "https://github.com/TeamSloppy/Sloppy/releases/download/v1.3.0/Sloppy-linux-x86_64.tar.gz"
  sha256 "40f41d6b97a07ed79ff44933aa38e8568991e389e5713a171d94ac480b664682"
  license "MIT"

  def install
    bin.install "bin/sloppy" => "sloppy"
    (share/"sloppy").install Dir["share/sloppy/*"]
  end

  test do
    system "#{bin}/sloppy", "--version"
  end
end

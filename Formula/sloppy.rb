class Sloppy < Formula
  desc "Agent runtime and dashboard for Sloppy"
  homepage "https://github.com/TeamSloppy/Sloppy"
  version "1.2.3"
  url "https://github.com/TeamSloppy/Sloppy/releases/download/v1.2.3/Sloppy-linux-x86_64.tar.gz"
  sha256 "28a3a18b6f047ea09593ef008a5130bcbfb90fd92d91829932081ab023673f86"
  license "MIT"

  def install
    bin.install "bin/sloppy" => "sloppy"
    (share/"sloppy").install Dir["share/sloppy/*"]
  end

  test do
    system "#{bin}/sloppy", "--version"
  end
end

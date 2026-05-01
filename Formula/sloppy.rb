class Sloppy < Formula
  desc "Agent runtime and dashboard for Sloppy"
  homepage "https://github.com/TeamSloppy/Sloppy"
  version "1.1.3"
  url "https://github.com/TeamSloppy/Sloppy/releases/download/v1.1.3/Sloppy-linux-x86_64.tar.gz"
  sha256 "c7df9a9b2e14422284efe25db5a7b08d88f6763f6b62bc65ec1cefe82f823999"
  license "MIT"

  def install
    bin.install "bin/sloppy" => "sloppy"
    (share/"sloppy").install Dir["share/sloppy/*"]
  end

  test do
    system "#{bin}/sloppy", "--version"
  end
end

class Sloppy < Formula
  desc "Agent runtime and dashboard for Sloppy"
  homepage "https://github.com/TeamSloppy/Sloppy"
  version "1.2.0"
  url "https://github.com/TeamSloppy/Sloppy/releases/download/v1.2.0/Sloppy-linux-x86_64.tar.gz"
  sha256 "62278154d93a2fe6ecc91032cfe4424c08b784255f71a88140565ae3c99075a9"
  license "MIT"

  def install
    bin.install "bin/sloppy" => "sloppy"
    (share/"sloppy").install Dir["share/sloppy/*"]
  end

  test do
    system "#{bin}/sloppy", "--version"
  end
end

class Sloppy < Formula
  desc "Agent runtime and dashboard for Sloppy"
  homepage "https://github.com/TeamSloppy/Sloppy"
  version "1.1.2"
  url "https://github.com/TeamSloppy/Sloppy/releases/download/v1.1.2/Sloppy-linux-x86_64.tar.gz"
  sha256 "89c44dc7e3f9954c5be3df64bb4b1e83636bcb35d8f02cde132b72ec7708fd64"
  license "MIT"

  def install
    bin.install "bin/sloppy" => "sloppy"
    bin.install "bin/SloppyNode" => "SloppyNode"
    (share/"sloppy").install Dir["share/sloppy/*"]
  end

  test do
    system "#{bin}/sloppy", "--version"
  end
end

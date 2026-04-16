class Sloppy < Formula
  desc "Agent runtime and dashboard for Sloppy"
  homepage "https://github.com/TeamSloppy/Sloppy"
  version "1.0.0"
  url "https://github.com/TeamSloppy/Sloppy/releases/download/v1.0.0/Sloppy-linux-x86_64.tar.gz"
  sha256 "273c3247aa3a7a308a2daa22ac145c6f67abc4f79ed2bb17ecb85f742ad7e6be"
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

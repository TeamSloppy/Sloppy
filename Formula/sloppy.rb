class Sloppy < Formula
  desc "Agent runtime and dashboard for Sloppy"
  homepage "https://github.com/TeamSloppy/Sloppy"
  version "1.3.2"
  url "https://github.com/TeamSloppy/Sloppy/releases/download/v1.3.2/Sloppy-linux-x86_64.tar.gz"
  sha256 "bcc7cffcbf5c4adc41aa3c8b015d0b10c7548e5194dbcd797cbc150e2e5f5d81"
  license "MIT"

  def install
    bin.install "bin/sloppy" => "sloppy"
    (share/"sloppy").install Dir["share/sloppy/*"]
  end

  test do
    system "#{bin}/sloppy", "--version"
  end
end

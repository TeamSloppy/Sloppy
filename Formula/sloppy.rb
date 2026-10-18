class Sloppy < Formula
  desc "Agent runtime and dashboard for Sloppy"
  homepage "https://github.com/TeamSloppy/Sloppy"
  version "2.5.0"
  url "https://github.com/TeamSloppy/Sloppy/releases/download/v2.5.0/Sloppy-linux-x86_64.tar.gz"
  sha256 "93bf0209eca20af09e70d72785eed4321478ca92179aadb7b7bf7118354ff82e"
  license "AGPL-3.0-only"

  def install
    bin.install "bin/sloppy" => "sloppy"
    (share/"sloppy").install Dir["share/sloppy/*"]
  end

  test do
    system "#{bin}/sloppy", "--version"
  end
end

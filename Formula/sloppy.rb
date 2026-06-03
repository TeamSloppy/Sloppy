class Sloppy < Formula
  desc "Agent runtime and dashboard for Sloppy"
  homepage "https://github.com/TeamSloppy/Sloppy"
  version "1.2.1"
  url "https://github.com/TeamSloppy/Sloppy/releases/download/v1.2.1/Sloppy-linux-x86_64.tar.gz"
  sha256 "cb0da27973a014efbe9191ca45fd7447e3440dfa2bd8477d2908340274958344"
  license "MIT"

  def install
    bin.install "bin/sloppy" => "sloppy"
    (share/"sloppy").install Dir["share/sloppy/*"]
  end

  test do
    system "#{bin}/sloppy", "--version"
  end
end

class Sloppy < Formula
  desc "Agent runtime and dashboard for Sloppy"
  homepage "https://github.com/TeamSloppy/Sloppy"
  version "1.2.2"
  url "https://github.com/TeamSloppy/Sloppy/releases/download/v1.2.2/Sloppy-linux-x86_64.tar.gz"
  sha256 "11c04780bfc1597f82f44b7819cfa7b4c3e7ecf2970fc2d2dc6b48a06a058ce7"
  license "MIT"

  def install
    bin.install "bin/sloppy" => "sloppy"
    (share/"sloppy").install Dir["share/sloppy/*"]
  end

  test do
    system "#{bin}/sloppy", "--version"
  end
end

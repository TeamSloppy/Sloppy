class Sloppy < Formula
  desc "Agent runtime and dashboard for Sloppy"
  homepage "https://github.com/TeamSloppy/Sloppy"
  version "1.2.4"
  url "https://github.com/TeamSloppy/Sloppy/releases/download/v1.2.4/Sloppy-linux-x86_64.tar.gz"
  sha256 "a511cf9200067bac76362c13463f99511fb0e58ff0a329b6bf6b86caae576eea"
  license "MIT"

  def install
    bin.install "bin/sloppy" => "sloppy"
    (share/"sloppy").install Dir["share/sloppy/*"]
  end

  test do
    system "#{bin}/sloppy", "--version"
  end
end

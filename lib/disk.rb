class Disk
  attr_accessor :tracks

  # TODO make adaptable sector handling

  def initialize
    self.tracks = []
  end

  def self.load(dir, debuglevel = 0)
    disk = self.new
    full_path = Pathname.new(dir).realpath
    pattern = full_path.join("*.trk")

    Dir.glob(pattern).sort.each { |filename|
      track = MfmTrack.load(filename, debuglevel)
      track.read_track

      sectors_read = (1..10).count { |i| track.sectors[i] && track.sectors[i].data.size == 512 }
      puts "read: track #{track.track_no}, side #{track.side}, sectors read: #{sectors_read}"

      disk.tracks << track
    }
    disk
  end

  def export(filename)
    str = ''

    tracks.sort_by{ |track| track.track_no * 2 + track.side }.each { |track|
      (1..10).each { |sector_no|
        sector = track.sectors[sector_no]
        sector.data.each { |c| str << c.chr }
      }
    }

    File.open(filename, "wb") { |f| f << str }

  end

end

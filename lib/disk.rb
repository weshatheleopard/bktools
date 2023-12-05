class Disk
  attr_accessor :tracks

  # TODO make adaptable sector handling

  def initialize
    self.tracks = []
  end

  # Load MFM disk (BK series)
  def self.load_mfm(dir, debuglevel = 0, sectors: 10)
    disk = self.new
    full_path = Pathname.new(dir).realpath
    pattern = full_path.join("*.trk")

    Dir.glob(pattern).sort.each { |filename|
      track = MfmTrack.load(filename, debuglevel, sectors: sectors)
      track.read

      msg = "Track #{track.track_no}, side #{track.side}, sectors read: #{track.successful_sectors}"

      if track.complete? then
        puts msg.green
      else
        puts msg.red
      end
      disk.tracks << track
    }
    puts "Tracks/sides read: #{disk.tracks.size}"
    disk
  end

  # Load FM disk (DVK series)
  def self.load_fm(dir, debuglevel = 0)
    disk = self.new
    full_path = Pathname.new(dir).realpath
    pattern = full_path.join("*.trk")

    Dir.glob(pattern).sort.each { |filename|
      track = FmTrack.load(filename, debuglevel)#, sectors: sectors)
      track.read
      track.side = disk.tracks.count { |trk| trk.track_no == track.track_no }

      msg = "Track #{track.track_no}, side #{track.side}, sectors read: #{track.successful_sectors}"

      if track.complete? then
        puts msg.green
      else
        puts msg.red
      end
      disk.tracks << track
    }
    puts "Tracks/sides read: #{disk.tracks.size}"
    disk
  end

  def export(filename)
    str = ''

    tracks.sort_by{ |track| track.track_no * 2 + track.side }.each { |track|
      (1..track.sectors_per_track).each { |sector_no|
        sector = track.sectors[sector_no]
        next if sector.nil?
        sector.data.each { |c| str << c.chr }
      }
    }

    File.open(filename, "wb") { |f| f << str }

  end

end

# https://zx-pk.ru/threads/20541-kontroller-kngmd-dvk-(-mx-)-i-rabotayushchie-s-nim-programmy.html
# Byte order: MSB, LSB (big-endian word)

require 'wavefile'
include WaveFile

require 'bit_stream'

class FmTrack
  attr_accessor :track_no, :side
  attr_accessor :fluxes, :indices
  attr_accessor :force_sync_pulse_length
  attr_accessor :debuglevel
  attr_accessor :sectors_per_track
  attr_accessor :sectors
  attr_reader :sector_params

  def initialize(debuglevel = 0)
    @debuglevel = debuglevel
    @sectors_per_track = 11
    @fluxes = []
    @indices = []
    @track_no = @side = nil
    @sync_pulse_length = nil
    @sectors = {}

    @sector_params = {}
  end

  def side_code(bit)
    case bit
    when 0 then "U"
    when 1 then "D"
    else "_"
    end
  end

  SOUND_FREQUENCY = 22050
  DIVISOR = 10

  # Method for saving track as wav for reviewing it in a sound editor
  def save_as_wav(filename)
    @buffer = Buffer.new([ ], Format.new(:mono, :pcm_16, SOUND_FREQUENCY))
    val = 30000
    fluxes.each_with_index { |v, i|
      round_val = (v.to_f / DIVISOR).to_i
      round_val = 1 if round_val == 0
      round_val.times { @buffer.samples << ((i.even?) ? 30000 : -30000 ) }
    }

    Writer.new("#{filename}.wav", Format.new(:mono, :pcm_8, SOUND_FREQUENCY)) { |writer| writer.write(@buffer) }
  end

  def save(filename_prefix, max_len: nil, with_line_numbers: false)
    scan # Detect track number

    path = Pathname.new(filename_prefix).dirname.realpath
    fn = Pathname.new(filename_prefix).basename

    out_fn = fn.to_s + "." + (self.track_no ? ("%02d" % self.track_no) : '_') + "." + side_code(self.side) + ".trk"
    out_path = Pathname.new(path).join(out_fn)

    File.open(out_path, "wb") { |f|
      f.puts "-----(#{force_sync_pulse_length})" if force_sync_pulse_length

      fluxes.each_with_index { |flux, pos|
        idx_no = indices.index(pos)
        f.puts "-----[#{idx_no + 1}]" if idx_no

        str = '%4i' % flux
        str << ' # %05i' % pos if with_line_numbers

        f.puts str
        break if max_len && (pos > max_len)
      }
      f.puts "=====END"
    }
  end

  def self.load(filename, debuglevel = 0, cleanup: nil)
    track = self.new(debuglevel)

    File.readlines(filename).each { |line|
      line = line.chomp
      if line =~ /^-----\[(\d+)\]\s*$/ then
        track.indices << track.fluxes.size
      elsif line =~ /^\s*(\d+)\s*(#.*)?$/ then
        track.fluxes << $1.to_i
      elsif line =~ /^\s*(\d+)\s+(\d+)\s*(#.*)?$/ then
        track.fluxes << ($1.to_i + $2.to_i)
      elsif line =~ /^\s*(\d+)\s+(\d+)\s+(\d+)\s*(#.*)?$/ then
        track.fluxes << ($1.to_i + $2.to_i + $3.to_i)
      elsif line =~ /^-----\((\d+(?:\.\d+)?)\)\s*$/ then
        track.force_sync_pulse_length = $1.to_f.round(1)
      end
    }

    track.cleanup(cleanup) if cleanup
    track
  end

  def sync_pulse_length
    return @force_sync_pulse_length if @force_sync_pulse_length
    @sync_pulse_length
  end

  def bucket(flux, spl = nil)
    spl ||= sync_pulse_length

    case
    when flux > (spl * 2.5) then 999
    when flux > (spl * 1.5) then 2
    when flux > (spl * 0.5) then 1
    else 1
    end
  end

  def find_track_marker(ptr, max_distance = nil)
    endptr = ptr + max_distance if max_distance

    magic_counter = 0

    loop do
      break if max_distance && (endptr < ptr)

      marker_candidate = fluxes[(ptr)..(ptr+21)]
      return(:EOF) if marker_candidate[13].nil?

      sync_pulse_length_candidate = (marker_candidate.inject(:+)) / 32.0

      if (# word "00F3"
          (bucket(marker_candidate[0], sync_pulse_length_candidate) == 2) &&
          (bucket(marker_candidate[1], sync_pulse_length_candidate) == 2) &&
          (bucket(marker_candidate[2], sync_pulse_length_candidate) == 2) &&
          (bucket(marker_candidate[3], sync_pulse_length_candidate) == 2) &&
          (bucket(marker_candidate[4], sync_pulse_length_candidate) == 2) &&
          (bucket(marker_candidate[5], sync_pulse_length_candidate) == 2) &&
          (bucket(marker_candidate[6], sync_pulse_length_candidate) == 2) &&
          (bucket(marker_candidate[7], sync_pulse_length_candidate) == 2) &&
          (bucket(marker_candidate[8], sync_pulse_length_candidate) == 1) &&
          (bucket(marker_candidate[9], sync_pulse_length_candidate) == 1) &&
          (bucket(marker_candidate[10], sync_pulse_length_candidate) == 1) &&
          (bucket(marker_candidate[11], sync_pulse_length_candidate) == 1) &&
          (bucket(marker_candidate[12], sync_pulse_length_candidate) == 1) &&
          (bucket(marker_candidate[13], sync_pulse_length_candidate) == 1) &&
          (bucket(marker_candidate[14], sync_pulse_length_candidate) == 1) &&
          (bucket(marker_candidate[15], sync_pulse_length_candidate) == 1) &&
          (bucket(marker_candidate[16], sync_pulse_length_candidate) == 2) &&
          (bucket(marker_candidate[17], sync_pulse_length_candidate) == 2) &&
          (bucket(marker_candidate[18], sync_pulse_length_candidate) == 1) &&
          (bucket(marker_candidate[19], sync_pulse_length_candidate) == 1) &&
          (bucket(marker_candidate[20], sync_pulse_length_candidate) == 1) &&
          (bucket(marker_candidate[21], sync_pulse_length_candidate) == 1)) then

        debug(10) { "0x00F3 Marker found @ ".green.bold + (ptr - 1).to_s.white.bold }
        debug(30) { "  * Fluxes recognized as magic word: #{marker_candidate.inspect}" }

        @sync_pulse_length = (marker_candidate.inject(:+) / 32.0).round(1)

        debug(15) { "Detected sync pulse length = #{@sync_pulse_length}".magenta }
        return (ptr)
      else
        ptr += 1

      end
    end
    return nil
  end
                             
  def read_flux(ptr)
    index_no = indices.index(ptr)
    if index_no then
      debug(20) { "----- Index marker #".magenta + index_no.to_s.white.bold + " @ ".magenta + ptr.to_s.white.bold }
    end
    flux = fluxes[ptr]
    debug(30) { "     Next flux read: ".yellow + flux.to_s.white.bold + " @ ".yellow + ptr.to_s.white.bold }

    if flux then
      if flux < (sync_pulse_length * 0.75) then # No flux is supposed to be this short
        debug(10) { "Format error: freshly red flux @ ".red + (ptr - 1).to_s.white.bold + " is too short: ".red + flux.to_s.white.bold }
      end
    end

    return flux, ptr + 1
  end

  def read_fm(ptr, len, start_state = nil)
    bitstream = BitStream.new
    bitstream.push(0, '0')

    flux, ptr = read_flux(ptr)

    loop do
      break if flux.nil?
      flux = flux.round(1)
      debug(20) { "Flux: #{flux}" }
      if flux > (sync_pulse_length * 2.5) then
        debug(30) { "ERROR: pulse too long".red }
      elsif flux > (sync_pulse_length * 1.5) then
        debug(30) { "[" + "0".bold + "]  No flux after sync pulse." }
        bitstream.push(ptr, '0')
      elsif flux > (sync_pulse_length * 0.5) then
        debug(30) { "[" + "1".bold + "]  Flux after sync pulse." }
        bitstream.push(ptr, '1')
        flux, ptr = read_flux(ptr)
        if (flux < (sync_pulse_length * 0.5))
          debug(30) { "ERROR: pulse too short after data pulse".red }
        elsif (flux > (sync_pulse_length * 1.5)) then
          debug(30) { "ERROR: pulse too long after data pulse".red }
        end
      else
        debug(30) { "ERROR: pulse too short".red }
      end

      flux, ptr = read_flux(ptr)

      break if len && (bitstream.size >= (len * 8 + 1))
    end

    if flux then
      return [ ptr - 1, bitstream ]
    else
      return(:EOF)
    end
  end

  def expect_byte(no, expected, actual)
    return true if (actual == expected)
    debug(15) { "Byte #".red + no.to_s.white.bold + ": Expected ".red + expected.white.bold + ", got ".red + actual.white.bold }
    return false
  end

  def scan
    read_track_header(0)
  end

  def read(keep_bad_data = false)
    ptr = sector_no = 0
    
    self.sectors = {}

    ptr = read_track_header(ptr)

    loop do
      sector = DiskSector.new(sector_no += 1, self)

      if ptr == :EOF then
        debug(2) { "---End of track".red }
        break
      end

      ptr, data, read_checksum, computed_checksum = read_sector_data(ptr, sector.size)

      if data then
        sector.data = data
      end

      if keep_bad_data || (read_checksum && computed_checksum && (read_checksum == computed_checksum)) then
        sector.read_checksum = read_checksum
        self.sectors[sector.number] = sector
      end

      break if successful_sectors == self.sectors_per_track
    end

    debug(3) { "Track #".green + track_no.to_s.white.bold +
                ": total sectors read: ".green + successful_sectors.to_s.white.bold }
    ptr
  end

  def debug(msg_level, newline: true)
    return if msg_level > @debuglevel
    msg = yield
    return unless msg
    if newline then
      puts(msg)
    else
      print(msg)
    end
  end

  def successful_sectors
    (1..self.sectors_per_track).count { |i| sectors[i] && sectors[i].valid? }
  end

  def complete?
    successful_sectors == self.sectors_per_track
  end

  def sectors_read
    sectors.keys.sort
  end

  def display(type = nil)
    (1..@sectors_per_track).each { |sector_no|
      puts "-----Side ".yellow + side.to_s.white.bold +
        '---Track '.yellow + ('%02d' % track_no).white.bold +
        '---Sector '.yellow + ('%02d' % sector_no).white.bold +
        '------------------------------------------------'.yellow
      sector = sectors[sector_no]
      if sector then
        sector.display(type)
      else
        puts "No data".red
      end
    }
    puts "---------------------------------------------------------------------------------".yellow
  end

  def read_track_header(ptr)
    debug(15) { "--- Reading track header".yellow }
    ptr = find_track_marker(ptr)

    return ptr if ptr == :EOF # End of track

    ptr, bitstream = read_fm(ptr, 4)


 bitstream.display


    return ptr if ptr == :EOF # End of track
    header_bytes = bitstream.to_bytes
    header = header_bytes.keys.sort.collect { |k| header_bytes[k] }

    debug(20) { "* Raw header data: #{header.inspect}" }

    return [ ptr, nil ] unless expect_byte(1, '00000000', header[0])
    return [ ptr, nil ] unless expect_byte(2, '11110011', header[1])
    self.track_no = header[3].to_i(2)
	
    debug(2) { "Track header:" }
    debug(3) { "  * Track:             ".blue.bold + self.track_no.to_s.bold }

    return ptr
  end

  def read_sector_data(ptr, sector_size)
    debug(15) { "--- Reading sector data, sector size = ".yellow + sector_size.to_s.white.bold }

    ptr, bitstream = read_fm(ptr, sector_size + 2)
    return(:EOF) if ptr == :EOF

    bytes = bitstream.to_bytes

    positions = bytes.keys.sort
    sector = positions.collect { |k| bytes[k] }

    bytes = nil
    data = []
    data = sector.each_slice(2).collect { |b1, b2| [ b2.to_i(2), b1.to_i(2)] }.flatten

    checksum_lo, checksum_hi = data.pop(2)
    read_checksum = (checksum_hi << 8) | checksum_lo

    computed_checksum = compute_data_checksum(data)

    debug(2) { "Sector data:" }
    debug(5) { "  * Read checksum:     ".blue.bold + read_checksum.to_s(2).rjust(16, '0').bold }
    debug(5) { "  * Computed checksum: ".blue.bold + computed_checksum.to_s(2).rjust(16, '0').bold }
    debug(2) { "  * Data checksum:     ".blue.bold + ((read_checksum == computed_checksum) ? 'success'.green : 'failed'.red) }

    [ ptr, data, read_checksum, computed_checksum ]
  end

  def compute_data_checksum(data)
    checksum = 0
    data.each_slice(2) { |b1, b2|
      word = (b2 << 8) | b1
      checksum = (checksum + word) & 0xFFFF
    }
    checksum
  end
end

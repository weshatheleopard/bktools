require 'wavefile'
include WaveFile

# TODO: read multiple revolutions and collect sectors that read well

class MfmTrack
  attr_reader :revolutions
  attr_accessor :track_no, :side

  def initialize(debuglevel = 0)
    @debuglevel = debuglevel
    @revolutions = []
    @track_no = @side = nil
    @sync_pulse_lengths = []
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
    @revolutions.each_with_index { |revolution, rev_no|

      @buffer = Buffer.new([ ], Format.new(:mono, :pcm_16, SOUND_FREQUENCY))
      val = 30000
      revolution.each_with_index { |v, i|
        round_val = (v.to_f / DIVISOR).to_i
        round_val = 1 if round_val == 0
        round_val.times { @buffer.samples << ((i.even?) ? 30000 : -30000 ) }
      }

      Writer.new("#{filename}.#{rev_no}.wav", Format.new(:mono, :pcm_8, SOUND_FREQUENCY)) { |writer| writer.write(@buffer) }
    }
  end

  def save(filename)
    path = Pathname.new(filename).dirname.realpath
    fn = Pathname.new(filename).basename

    out_fn = "%s.%02u.%s.trk" % [ fn, self.track_no, side_code(self.side) ]
    out_path = Pathname.new(path).join(out_fn)

    File.open(out_path, "wb") { |f|
      @revolutions.each_with_index { |revolution, rev_no|
        f.puts "-----[#{rev_no}]"
        revolution.each_with_index { |flux, idx|
          f.puts "%4i # %05i" % [ flux, idx ]
        }
      }
      f.puts "=====END"
    }
  end

  def analyze(start = nil, len = nil, revolution_to_analyze = 1)
    sync_pulse_length = determine_sync_pulse_length(revolution_to_analyze)

    @revolutions.each_with_index { |revolution, rev_no|
      puts "-----[#{rev_no}]".yellow

      revolution&.each_with_index { |flux, idx|
        next if (start && (idx < start)) || (len && (idx > start + len))
        s = "%4i # %07i" % [ flux, idx ]

        # Magic = 43431, where 1 = sync length
        if flux > (sync_pulse_length * 2.25) then
          puts s.red.bold
        elsif flux > (sync_pulse_length * 1.9) then # Special case - synhro A1 (10100O01)
          puts s.green.bold
        elsif flux < (sync_pulse_length * 0.75) then
          puts s.red.bold
        else
          puts s.green
        end
      }
    }
  end

  def self.load(filename, debuglevel = 0)
    track = self.new(debuglevel)
    current_revolution = []
    idx = nil

    File.readlines(filename).each { |line|
      if line =~ /^-----\[(\d+)\]\s*$/ then
        idx && track.revolutions[idx] = current_revolution
        current_revolution = []
        idx = $1.to_i
      elsif line =~ /^\s*(\d+)(\s*#.+)?$/ then
        current_revolution << ($1.to_i)
      end
    }

    idx && track.revolutions[idx] = current_revolution
    track
  end

  # Track starts with a bun
  def determine_sync_pulse_length(revolution_to_analyze)
    return if @revolutions[revolution_to_analyze].nil?
    sync_pulse_length = @sync_pulse_lengths[revolution_to_analyze]
    return sync_pulse_length if sync_pulse_length

    sum = counter = sync_pulse_length = 0

    current_idx = nil

    revolutions[revolution_to_analyze].each_with_index { |flux, i|
      current_idx = i
      sum += flux
      sync_pulse_length = sum.to_f / (i + 1)

      break if (i > 1) && (((flux / sync_pulse_length) - 1).abs > 0.15) # The speed detection run is done
    }

    sync_pulse_length = sync_pulse_length.round(1)

    debug(15) { "Sync pulse length determined to be " + sync_pulse_length.to_s.white + " @ ".green + current_idx.to_s.white.bold }

    @sync_pulse_lengths[revolution_to_analyze] = sync_pulse_length
  end

  def find_marker(ptr, revolution_to_analyze, max_distance = nil)
    sync_pulse_length = determine_sync_pulse_length(revolution_to_analyze)
    current_revolution = revolutions[revolution_to_analyze]
    endptr = nil
    endptr = ptr + max_distance if max_distance

    stream = '-' * 15

    flux = 0
    loop do
      break if endptr && (endptr < ptr)
      flux = current_revolution[ptr]
      break if flux.nil?
      flux = flux.round(1)

      pulse = case flux
              when ((sync_pulse_length * 1.75) .. (sync_pulse_length * 2.25)) then
                "4"
              when ((sync_pulse_length * 1.25) .. (sync_pulse_length * 1.75)) then
                "3"
              when ((sync_pulse_length * 0.75) .. (sync_pulse_length * 1.25)) then
                "2"
              else
                "*"
              end

      stream = stream[1..14] + pulse

      if stream[11..15] == "4343" then
        debug(15) { "Magic word found @ ".green + (ptr - 4).to_s.white.bold }
      end

      if stream == "434324343243432" then
        debug(10) { "Magic sequence found @ ".green.bold + (ptr - 15).to_s.white.bold }
        return ptr - 15
      end

      ptr += 1
    end

    return nil
  end

  def read_mfm(ptr, len, revolution_to_analyze)
    current_revolution = revolutions[revolution_to_analyze]
    bitstream = ''
    sync_pulse_length = determine_sync_pulse_length(revolution_to_analyze)

    debug(18) { "Sync pulse length = #{sync_pulse_length}" }

    flux = current_revolution[ptr]
    ptr += 1

    loop do
      break if flux.nil?
      flux = flux.round(1)
      debug(20) { "Flux @ #{ptr}: #{flux}" }

      if flux > (sync_pulse_length * 1.75) then # Special case - synhro A1 (10100O01)
        debug(30) { "[" + "0o".bold + "] Current flux > 7/4 sync pulse. Special case of sector marker." }
        bitstream << '0o'
        flux = current_revolution[ptr]
        debug(30) { "     Next flux read: #{flux}".yellow }
        ptr += 1
      elsif flux > sync_pulse_length then
        debug(30) { "[" + "0".bold + "]  Current flux longer than sync pulse." }
        bitstream << '0'
        flux = flux - sync_pulse_length
      elsif flux > (sync_pulse_length * 0.75) then
        debug(30) { "[" + "0".bold + "]  Current flux between 3/4 and 1 sync pulse, stretching it to full." }
        bitstream << '0'
        flux = current_revolution[ptr]
        debug(30) { "     Next flux read: #{flux}".yellow }
        ptr += 1
      elsif flux < (sync_pulse_length * 0.25) then # Tiny reminder of previous flux
        debug(30) { "     Current flux less than 1/4 sync pulse, considering it a remainder of a previous flux" }
        flux = current_revolution[ptr]
        debug(30) { "     Next flux read: #{flux}".yellow }
        ptr += 1
      else
        debug(30) { "[" + "1".bold + "]  Current flux between 1/4 and 3/4 sync pulse." }
        bitstream << '1'
        flux = current_revolution[ptr]
        debug(30) { "     Next flux read: #{flux}".yellow }
        ptr += 1
        flux = flux - (sync_pulse_length / 2)
      end

      break if len && (bitstream.size >= (len * 8 + 1))
    end

    if flux then
      return [ ptr, bitstream  ]
    else
      return nil
    end
  end

  def expect_byte(no, expected, actual)
    if actual != expected then
      debug(15) { "Byte #".red + no.to_s.white.bold + ": Expected ".red + expected.white.bold + ", got ".red + actual.white.bold }
      return false
    else
      return true
    end
  end

  def read_sector_header(ptr, revolution_to_analyze)
    debug(15) { "--- Reading sector header".yellow }
    ptr = find_marker(ptr, revolution_to_analyze)

    return nil if ptr.nil? # End of track

    ptr, bitstream = read_mfm(ptr, 4 + 4 + 2, revolution_to_analyze)
    header = bitstream[1..-1].unpack "A8A8A8A8A8A8A8A8A8A8"

    debug(20) { "* Raw header data: #{header.inspect}" }

    return [ ptr, nil ] unless expect_byte(1, '10100o01', header.shift)
    return [ ptr, nil ] unless expect_byte(2, '10100o01', header.shift)
    return [ ptr, nil ] unless expect_byte(3, '10100o01', header.shift)
    return [ ptr, nil ] unless expect_byte(4, '11111110', header.shift)
    header.map! { |b| b.to_i(2) }

    b0 = header.pop
    b1 = header.pop
    read_checksum = Tools::bytes2word(b0, b1)

    computed_checksum = crc_ccitt([0xa1, 0xa1, 0xa1, 0xfe] + header)

    track_read = header.shift
    side_read = header.shift
    sector_no = header.shift
    sector_size_code = header.shift

    debug(1) { "Sector header:" }
    debug(2) { "  * Track:             ".blue.bold + track_read.to_s.bold }
    debug(2) { "  * Side:              ".blue.bold + side_read.to_s.bold }
    debug(2) { "  * Sector #:          ".blue.bold + sector_no.to_s.bold }
    debug(3) { "  * Sector size:       ".blue.bold + sector_size_code.to_s.bold }
    debug(5) { "  * Computed checksum: " + Tools::zeropad(computed_checksum.to_s(2), 16).bold }
    debug(5) { "  * Read checksum:     " + Tools::zeropad(read_checksum.to_s(2), 16).bold }
    debug(1) { "  * Header checksum:   " + ((read_checksum == computed_checksum) ? 'success'.green : 'failed'.red) }

    if read_checksum == computed_checksum then
      if self.track_no.nil? then
        self.track_no = track_read
      elsif self.track_no != track_read then
        debug(0) { "---!!! Track number mismatch: existing #{self.track_no}, read #{track_read}".red }
      end

      if self.side.nil? then
        self.side = side_read
      elsif self.side != side_read then
        debug(0) { "---!!! Side mismatch: existing #{self.side}, read #{side_read}".red }
      end
    end

    [ ptr, track_read, side_read, sector_no, sector_size_code ]
  end

  def read_sector_data(ptr, revolution_to_analyze)
    debug(15) { "--- Reading sector data".yellow }
    ptr = find_marker(ptr, revolution_to_analyze, 400)
    return nil if ptr.nil?

    ptr, bitstream = read_mfm(ptr, 4 + 512 + 2, revolution_to_analyze)
    sector = bitstream[1..-1].unpack "A8A8A8A8A4096A8A8"

    return [ ptr, nil ] unless expect_byte(1, '10100o01', sector.shift)
    return [ ptr, nil ] unless expect_byte(2, '10100o01', sector.shift)
    return [ ptr, nil ] unless expect_byte(3, '10100o01', sector.shift)
    return [ ptr, nil ] unless expect_byte(4, '11111011', sector.shift)

    data = sector.shift.scan(/\d{8}/).map! { |b| b.to_i(2) }

    b0 = sector.pop.to_i(2)
    b1 = sector.pop.to_i(2)

    read_checksum = Tools::bytes2word(b0, b1)
    computed_checksum = crc_ccitt([0xa1, 0xa1, 0xa1, 0xfb] + data)

    debug(1) { "Sector data:" }
    debug(5) { "  * Computed checksum: " + Tools::zeropad(computed_checksum.to_s(2), 16).bold }
    debug(5) { "  * Read checksum:     " + Tools::zeropad(read_checksum.to_s(2), 16).bold }
    debug(1) { "  * Header checksum:   " + ((read_checksum == computed_checksum) ? 'success'.green : 'failed'.red) }

    [ ptr, data, read_checksum == computed_checksum ]
  end

  def scan_track(revolution_to_analyze)
    # Read just the sector headers
    ptr = 0

    loop {
      data = read_sector_header(ptr, revolution_to_analyze)
      break if data.nil?

      ptr, track, side, sector = data
      next if track.nil?

      if ptr.nil? then
        debug(1) { "---EOF".red }
        break
      end
    }
  end

  def read_revolution(revolution_to_analyze = 1, keep_bad_data = false)
    ptr = 0
    data_hash = {}

    loop do
      if ptr.nil? then
        debug(1) { "---EOF".red }
        break
      end

      ptr, track, side, sector_no, sector_size_code = read_sector_header(ptr, revolution_to_analyze)
      next if track.nil?

      if ptr.nil? then
        debug(1) { "---EOF".red }
        break
      end

      sector = DiskSector.new(sector_no, sector_size_code)
      ptr, sector.data, crc_matched = read_sector_data(ptr, revolution_to_analyze)
      data_hash[sector.number] = sector if crc_matched || keep_bad_data
    end

    debug(8) { "Revolution #".green + revolution_to_analyze.to_s.white.bold +
                 ": sectors read: ".green + data_hash.to_a.count{ |pair| !pair.last.nil? }.to_s.white.bold }

    return data_hash
  end

  def read_track()
    all_sectors = {}

    (1..revolutions.size).each do |rev|
      next if revolutions[rev].nil?
      debug(3) { "-----Reading revolution #".yellow + rev.to_s.white.bold + " -----------------------------------".yellow }
      rev_sectors = read_revolution(rev)
      rev_sectors.each_pair { |idx, sector|
        all_sectors[sector.number] = sector if all_sectors[sector.number].nil?
      }
    end

    debug(3) { "Track #".green + track_no.to_s.white.bold +
                ": total sectors read: ".green + all_sectors.to_a.count{ |pair| !pair.last.nil? }.to_s.white.bold }
    all_sectors
  end

  def debug(msg_level)
    return if msg_level > @debuglevel
    msg = yield
    puts(msg) if msg
  end

  def crc_ccitt(byte_array)
    crc = 0xffff

    byte_array.each { |b|
      crc ^= (b << 8)
      8.times { crc = ((crc & 0x8000)!=0) ? ((crc << 1) ^ 0x1021) : (crc << 1) }
    }

    return crc & 0xffff
  end

end

# track = MfmTrack.load("track001...trk")


require 'wavefile'
include WaveFile

class MfmTrack
  attr_reader :revolutions
  attr_accessor :track_no, :side, :revolution_to_analyze

  def initialize(debuglevel = 0)
    @debuglevel = debuglevel
    @revolutions = []
    @revolution_to_analyze = 1 # Revolution #0 tends to be incomplete
    @track_no = @side = nil
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
    File.open("%s.%02u.%s.trk" % [filename, self.track_no, side_code(self.side) ], "wb") { |f|
      @revolutions.each_with_index { |revolution, rev_no|
        f.puts "-----[#{rev_no}]"
        revolution.each_with_index { |flux, idx|
          f.puts "%4i # %05i" % [ flux, idx ]
        }
      }
      f.puts "=====END"
    }
  end

  def analyze
    sync_pulse_length = determine_sync_pulse_length

    @revolutions.each_with_index { |revolution, rev_no|
      puts "-----[#{rev_no}]".yellow
      revolution.each_with_index { |flux, idx|
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
      if line =~ /^-----\[(\d+)\]$/ then
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
  def determine_sync_pulse_length
    return if @revolutions[@revolution_to_analyze].nil?
    return @sync_pulse_length if @sync_pulse_length

    sum = counter = sync_pulse_length = 0

    revolutions[@revolution_to_analyze].each_with_index { |flux, i|
      sum += flux
      sync_pulse_length = sum.to_f / (i + 1)

      break if (i > 1) && (((flux / sync_pulse_length) - 1).abs > 0.15) # The speed detection run is done
    }

    @sync_pulse_length = sync_pulse_length.round(2)
  end

  def find_marker(ptr = 0)
    sync_pulse_length = determine_sync_pulse_length

    str = "0000"    

    flux = 0
    until flux.nil? do
      flux = revolutions[@revolution_to_analyze][ptr]
      flux = flux.round(1)

      pulse = case flux
              when ((sync_pulse_length * 1.75) .. (sync_pulse_length * 2.25)) then
                "4"
              when ((sync_pulse_length * 1.25) .. (sync_pulse_length * 1.75)) then
                "3"
              else
                "*"
              end

      str = str[1..3] + pulse

      if str == "4343" then
        debug(10) { "Magic sequence found @ #{ptr - 4}" }
        return ptr - 4
      end

      ptr += 1
    end

    return nil
  end

  def read_mfm(ptr, len = nil)
    bitstream = ''
    sync_pulse_length = determine_sync_pulse_length

    debug(15) { "Sync pulse length = #{sync_pulse_length}" }

    flux = revolutions[@revolution_to_analyze][ptr]
    ptr += 1

    until flux.nil? do
      flux = flux.round(1)
      debug(20) { "Current flux length: #{flux}" }

      if flux > (sync_pulse_length * 1.75) then # Special case - synhro A1 (10100O01)
        debug(30) { "[" + "0o".bold + "] Current flux > 7/4 sync pulse. Special case of sector marker." }
        bitstream << '0o'
        flux = revolutions[@revolution_to_analyze][ptr]
        debug(30) { "     Next flux read: #{flux}".yellow }
        ptr += 1
      elsif flux > sync_pulse_length then
        debug(30) { "[" + "0".bold + "]  Current flux longer than sync pulse." }
        bitstream << '0'
        flux = flux - sync_pulse_length
      elsif flux > (sync_pulse_length * 0.75) then
        debug(30) { "[" + "0".bold + "]  Current flux between 3/4 and 1 sync pulse, stretching it to full." }
        bitstream << '0'
        flux = revolutions[@revolution_to_analyze][ptr]
        debug(30) { "     Next flux read: #{flux}".yellow }
        ptr += 1
      elsif flux < (sync_pulse_length * 0.25) then # Tiny reminder of previous flux
        debug(30) { "     Current flux less than 1/4 sync pulse, considering it a remainder of a previous flux" }
        flux = revolutions[@revolution_to_analyze][ptr]
        debug(30) { "     Next flux read: #{flux}".yellow }
        ptr += 1
      else
        debug(30) { "[" + "1".bold + "]  Current flux between 1/4 and 3/4 sync pulse." }
        bitstream << '1'
        flux = revolutions[@revolution_to_analyze][ptr]
        debug(30) { "     Next flux read: #{flux}".yellow }
        ptr += 1
        flux = flux - (sync_pulse_length / 2)
      end

      break if len && (bitstream.size == (len * 8 + 1)) 
    end

    [ ptr, bitstream  ]
  end

  def read_sector_header(ptr)
    debug(15) { "--- Reading sector header".yellow }
    ptr = find_marker(ptr)
    ptr, bitstream = read_mfm(ptr, 4 + 4 + 2)
    header = bitstream[1..-1].unpack "A8A8A8A8A8A8A8A8A8A8"

    debug(20) { "* Raw header data: #{header.inspect}" }

    return if header.shift != '10100o01'
    return if header.shift != '10100o01'
    return if header.shift != '10100o01'
    header.map! { |b| b.to_i(2) }
    return if header.shift != 0xfe

    b0 = header.pop
    b1 = header.pop
    read_checksum = Tools::bytes2word(b0, b1)

    computed_checksum = crc_ccitt([0xa1, 0xa1, 0xa1, 0xfe] + header)

    track_read = header.shift
    side_read = header.shift
    sector_no = header.shift
    sector_size_code = header.shift

    debug(1) { "Sector header:" }
    debug(1) { "  * Track:             ".blue.bold + track_read.to_s.bold }
    debug(1) { "  * Side:              ".blue.bold + side_read.to_s.bold }
    debug(1) { "  * Sector #:          ".blue.bold + sector_no.to_s.bold }
    debug(1) { "  * Sector size:       ".blue.bold + sector_size_code.to_s.bold }
    debug(1) { "  * Read checksum:     #{read_checksum.to_s.bold}" }
    debug(1) { "  * Computed checksum: #{computed_checksum.to_s.bold}" }
    debug(1) { "  * Header checksum:   #{(read_checksum == computed_checksum) ? 'success'.green : 'failed'.red }" }

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

  def read_sector_data(ptr)
    debug(15) { "--- Reading sector data".yellow }
    ptr = find_marker(ptr)
    ptr, bitstream = read_mfm(ptr, 4 + 512 + 2)
    sector = bitstream[1..-1].unpack "A8A8A8A8A4096A8A8"

    return if sector.shift != '10100o01'
    return if sector.shift != '10100o01'
    return if sector.shift != '10100o01'
    return if sector.shift.to_i(2) != 0xfb

    data = sector.shift.scan(/\d{8}/).map! { |b| b.to_i(2) }

    b0 = sector.pop.to_i(2)
    b1 = sector.pop.to_i(2)

    read_checksum = Tools::bytes2word(b0, b1)
    computed_checksum = crc_ccitt([0xa1, 0xa1, 0xa1, 0xfb] + data)

    debug(1) { "Sector data:" }
    debug(1) { "  * Read checksum:     #{read_checksum.to_s.bold}" }
    debug(1) { "  * Computed checksum: #{computed_checksum.to_s.bold}" }
    debug(1) { "  * Data checksum:     #{(read_checksum == computed_checksum) ? 'success'.green : 'failed'.red }" }

    [ ptr, data ]
  end

  def read_track
    ptr = 0

    10.times {
      ptr, track, side, sector = read_sector_header(ptr)
      ptr, data = read_sector_data(ptr)
    }
  end
    
  def debug(msg_level)
    return if msg_level > @debuglevel
    msg = yield
    puts(msg) if msg
  end

  def crc_ccitt(byte_array)
    crc = 0xffff;

    byte_array.each { |b|
      crc ^= (b << 8)
      8.times { crc = ((crc & 0x8000)!=0) ? ((crc << 1) ^ 0x1021) : (crc << 1) }
    }

    return crc & 0xffff
  end


end

# track = MfmTrack.load("track001...trk")
# f  = FddReader.new "", 10
# f.fluxes2bitstream track, 1

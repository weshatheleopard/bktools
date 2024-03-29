require 'disk_track'
require 'bit_stream'

class MfmTrack < DiskTrack
  attr_accessor :side, :sectors
  attr_reader :sector_params

  def initialize(debuglevel = 0, sectors: 10)
    @debuglevel = debuglevel
    @fluxes = []
    @indices = []
    @track_no = @side = nil
    @sync_pulse_length = nil
    @sectors = {}

    @sector_params = {}
    super
  end

  def save(filename, max_len = nil, with_line_numbers = false)
    path = Pathname.new(filename).dirname.realpath
    fn = Pathname.new(filename).basename

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

  def analyze(start = nil, len = nil)
    sync_pulse_length = scan # Establish sync pulse length

    fluxes.each_with_index { |flux, pos|
      next if (start && (pos < start)) || (len && (pos > start + len))

      idx_no = indices.index(pos)
      puts "-----[#{idx_no}]".yellow if idx_no

      s = "%4i # %07i" % [ flux, pos ]

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
  end

  def self.load(filename, debuglevel = 0, cleanup: nil, sectors: 10)
    track = self.new(debuglevel, sectors: sectors)

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

  def bucket(flux, spl = nil)
    spl ||= sync_pulse_length

    case
    when flux > (spl * 2.25) then 999
    when flux > (spl * 1.75) then 4
    when flux > (spl * 1.25) then 3
    when flux > (spl * 0.75) then 2
    else 1
    end
  end

  def find_marker(ptr, max_distance = nil)
    endptr = ptr + max_distance if max_distance

    magic_counter = 0

    loop do
      break if max_distance && (endptr < ptr)

      marker_candidate = fluxes[(ptr)..(ptr+4)]
      return(:EOF) if marker_candidate[4].nil?

      sync_pulse_length_candidate = (marker_candidate.inject(:+)) / 8.0

      if ((sync_pulse_length_candidate > 30) &&
          (bucket(marker_candidate[0], sync_pulse_length_candidate) == 4) &&
          (bucket(marker_candidate[1], sync_pulse_length_candidate) == 3) &&
          (bucket(marker_candidate[2], sync_pulse_length_candidate) == 4) &&
          (bucket(marker_candidate[3], sync_pulse_length_candidate) == 3) &&
          (bucket(marker_candidate[4], sync_pulse_length_candidate) == 2)) then

        debug(15) { "Magic word (#{magic_counter}) found @ ".green + ptr.to_s.white.bold }
        debug(30) { "  * Fluxes recognized as magic word: #{marker_candidate.inspect}" }

        ptr += 5
        magic_counter +=1

        if magic_counter == 3 then
          debug(10) { "Magic sequence found @ ".green.bold + (ptr - 15).to_s.white.bold }

          marker = fluxes[(ptr - 15)..(ptr - 1)]
          @sync_pulse_length = (marker.inject(:+) / 24.0).round(1)

          debug(15) { "Detected sync pulse length = #{@sync_pulse_length}".magenta }
          return(ptr - 16)
        end
      else
        magic_counter = 0
        ptr +=1
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

  def read_mfm(ptr, len, start_state = nil)
    bitstream = BitStream.new

    flux, ptr = read_flux(ptr)

    # If start state is not specified, we assume reading starts at the marker, which is preceded by a zero bit,
    # and that means pre-marker impulse oughtta be 1.5x
    if (start_state.nil? && (flux < (sync_pulse_length * 1.25)) || (start_state == 1)) then
      debug(15) { "Pre-maker pulse too short (".magenta + flux.to_s.white.bold + ") @".magenta + ptr.to_s.white.bold + ", lengthening".magenta }
      flux = sync_pulse_length * 1.5
    elsif (flux > (sync_pulse_length * 1.75)) then
      debug(15) { "Pre-maker pulse too long (".magenta + flux.to_s.white.bold + ") @".magenta + ptr.to_s.white.bold + ", shortening".magenta }
      flux = sync_pulse_length * 1.5
    end

    leftover = false

    loop do
      break if flux.nil?
      flux = flux.round(1)
      debug(20) { "Flux: #{flux}" }

      if flux > (sync_pulse_length * 1.75) then # Special case - synhro A1 (10100O01)
        debug(30) { "[" + "0o".bold + "] Current flux > 7/4 sync pulse. Special case of sector marker.".magenta }
        bitstream.push(ptr, '0o')
        flux, ptr = read_flux(ptr)
        leftover = false
      elsif flux > sync_pulse_length then # Probably should be * 1.25 here
        debug(30) { "[" + "0".bold + "]  Current flux longer than sync pulse." }
        bitstream.push(ptr, '0')
        flux = flux - sync_pulse_length
        leftover = true
      elsif flux > (sync_pulse_length * 0.75) then
        debug(30) { "[" + "0".bold + "]  Current flux between 3/4 and 1 sync pulse, stretching it to full." }
        bitstream.push(ptr, '0')
        flux, ptr = read_flux(ptr)
        leftover = false
      elsif flux < (sync_pulse_length * 0.25) then # Tiny reminder of previous flux
        debug(30) { "     Current flux less than 1/4 sync pulse, considering it a remainder of a previous flux" }
        flux, ptr = read_flux(ptr)
        leftover = false
      else
        debug(30) { "[" + "1".bold + "]  Current flux between 1/4 and 3/4 sync pulse." }

        if !leftover then
          debug(10) { "Format error: freshly red flux @ ".red + (ptr - 1).to_s.white.bold + " is too short: ".red + flux.to_s.white.bold + ". Expanding to full flux.".red }
          flux = sync_pulse_length
        end

        bitstream.push(ptr, '1')
        flux, ptr = read_flux(ptr)
        return(:EOF) if flux.nil?
        flux = flux - (sync_pulse_length / 2)
        leftover = true
      end

      break if len && (bitstream.size >= (len * 8 + 1))
    end

    if flux then
      return [ ptr, bitstream ]
    else
      return(:EOF)
    end
  end

  def read_sector_header(ptr)
    debug(15) { "--- Reading sector header".yellow }
    ptr = find_marker(ptr)
    return ptr if ptr == :EOF # End of track

    ptr, bitstream = read_mfm(ptr, 4 + 4 + 2)
    return ptr if ptr == :EOF # End of track
    header_bytes = bitstream.to_bytes
    header = header_bytes.keys.sort.collect { |k| header_bytes[k] }

    debug(20) { "* Raw header data: #{header.inspect}" }

    return [ ptr, nil ] unless expect_byte(1, '10100o01', header.shift)
    return [ ptr, nil ] unless expect_byte(2, '10100o01', header.shift)
    return [ ptr, nil ] unless expect_byte(3, '10100o01', header.shift)
    return [ ptr, nil ] unless expect_byte(4, '11111110', header.shift)
    header.map! { |b| b.to_i(2) }

    b_low  = header.pop
    b_high = header.pop

    read_checksum = Tools::bytes2word(b_low, b_high)
    computed_checksum = Tools::crc_ccitt([0xA1, 0xA1, 0xA1, 0xFE] + header)

    track_read = header.shift
    side_read = header.shift
    sector_no = header.shift
    sector_size_code = header.shift

    debug(2) { "Sector header:" }
    debug(3) { "  * Track:             ".blue.bold + track_read.to_s.bold }
    debug(4) { "  * Side:              ".blue.bold + side_read.to_s.bold }
    debug(4) { "  * Sector #:          ".blue.bold + sector_no.to_s.bold }
    debug(5) { "  * Sector size code:  ".blue.bold + sector_size_code.to_s.bold }
    debug(5) { "  * Computed checksum: ".blue.bold + computed_checksum.to_s(2).rjust(16, '0').bold }
    debug(5) { "  * Read checksum:     ".blue.bold + read_checksum.to_s(2).rjust(16, '0').bold }
    debug(2) { "  * Header checksum:   ".blue.bold + ((read_checksum == computed_checksum) ? 'success'.green : 'failed'.red) }

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
      return [ ptr, track_read, side_read, sector_no, sector_size_code ]
    else
      return [ ptr ]
    end

  end

  def read_sector_data(ptr, sector_size)
    debug(15) { "--- Reading sector data, sector size = ".yellow + sector_size.to_s.white.bold }

    res = find_marker(ptr, 400)
    return(:EOF) if res == :EOF
    return(ptr + 15) if res.nil?

    ptr, bitstream = read_mfm(res, 4 + sector_size + 2)
    return(:EOF) if ptr == :EOF

    bytes = bitstream.to_bytes
    positions = bytes.keys.sort
    sector = positions.collect { |k| bytes[k] }

    return [ ptr, nil ] unless expect_byte(1, '10100o01', sector.shift)
    return [ ptr, nil ] unless expect_byte(2, '10100o01', sector.shift)
    return [ ptr, nil ] unless expect_byte(3, '10100o01', sector.shift)
    return [ ptr, nil ] unless expect_byte(4, '11111011', sector.shift)

    b_low = sector.pop.to_i(2)
    b_high = sector.pop.to_i(2)

    data = sector.each_with_index.collect { |b, i|
        if b =~ /o/ then
          debug(6) { "Format error: sector contains a too long of a pulse @ ".red.bold + positions[i + 4].to_s.white.bold }
          0
        else b.to_i(2)
        end
      }

    # This is should be the first check, but then we won't see the debug message about messed up bits
    if (sector.size != sector_size) then
      debug(2) { "Sector size mismatch: expected ".red + sector_size.to_s.white + ", got ".red + sector.size.to_s.white }
      return [ ptr, data ]
    end

    read_checksum = Tools::bytes2word(b_low, b_high)
    computed_checksum = compute_data_checksum(data)

    debug(2) { "Sector data:" }
    debug(5) { "  * Read checksum:     ".blue.bold + read_checksum.to_s(2).rjust(16, '0').bold }
    debug(5) { "  * Computed checksum: ".blue.bold + computed_checksum.to_s(2).rjust(16, '0').bold }
    debug(2) { "  * Data checksum:     ".blue.bold + ((read_checksum == computed_checksum) ? 'success'.green : 'failed'.red) }

    [ ptr, data, read_checksum, computed_checksum ]
  end

  def scan
    # Read just the sector headers
    ptr = 0
    loop {
      ptr, track, side, sector, sector_size_code = read_sector_header(ptr)

      return @sync_pulse_length unless track.nil?

      if ptr == :EOF then
        debug(2) { "---End of track".red }
        return :EOF
        break
      end
    }
  end

  def find_sync_pulse_length
    debug(1) { "Detecting sync pulse length".green }
    average_pulse_length = self.scan
    arr = [ average_pulse_length ]

    1.upto(30) do |i|
     arr << average_pulse_length + (0.1 * i)
     arr << average_pulse_length - (0.1 * i)
    end

    arr.each { |sync_pulse_length_candidate|
      self.force_sync_pulse_length = sync_pulse_length_candidate
      debug(3) { "Attempting: ".green + sync_pulse_length_candidate.round(1).to_s.yellow  }
      self.read
      return sync_pulse_length_candidate if self.complete?
    }

    return nil
  end

  def read(keep_bad_data = false)
    ptr = 0

    self.sectors = {}
    loop do
      if ptr == :EOF then
        debug(2) { "---End of track".red }
        break
      end

      ptr, track, side, sector_no, sector_size_code = read_sector_header(ptr)
      next if track.nil?

      if ptr == :EOF then
        debug(2) { "---End of track".red }
        break
      end

      sector = DiskSector.new(sector_no, self, sector_size_code)
      next if sector.size.nil? # Start over if sector header is messed up

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

  # Find locations of sectors in the track for manual review
  def detect_sectors
    ptr = 0
    @sector_params = {}

    loop do
      header_marker_ptr = find_marker(ptr)
      break if header_marker_ptr == :EOF
      ptr, track_no, side, sector_no, sector_size_code = read_sector_header(header_marker_ptr)

      if track_no then
        data_marker_ptr = find_marker(ptr, 400)
        if data_marker_ptr then
          @sector_params[sector_no] ||=[]
          @sector_params[sector_no] << data_marker_ptr
          ptr = data_marker_ptr + 16
        end
      end
    end

    @sector_params
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

  def compute_data_checksum(data)
    Tools::crc_ccitt([0xA1, 0xA1, 0xA1, 0xFB] + data)
  end

  # For not so well scanned tracks: attempt to straighten the signal
  def cleanup(sync_pulse_length)
    debug(5) { "Pass 1: abnormally long pulse surrounded by abnormally short pulses".green }
    loop do
      changes_made = 0
      (1..(fluxes.size - 2)).each do |i|
        if (fluxes[i - 1] < sync_pulse_length) &&
           (fluxes[i] > 2 * sync_pulse_length) &&
           (fluxes[i + 1] < sync_pulse_length) then
          changes_made += 1
          fluxes[i-1] += 1
          fluxes[i + 1] += 1
          fluxes[i] -= 2
        end
      end
      debug(5, newline: false) { "#{changes_made} ".white }
      break if changes_made == 0
    end

    debug(5) { "\nPass 2: long pulse surrounded by abnormally short pulses".green }
    loop do
      changes_made = 0
      (1..(fluxes.size - 2)).each do |i|
        if (fluxes[i - 1] < sync_pulse_length) &&
           (((fluxes[i] > sync_pulse_length * 1.5)) && (fluxes[i] < (sync_pulse_length * 1.8))) &&
           (fluxes[i + 1] < sync_pulse_length) then
          changes_made += 1
          fluxes[i-1] += 1
          fluxes[i] -= 2
          fluxes[i+1] += 1
        end
      end

      debug(5, newline: false) { "#{changes_made} ".white }
      break if changes_made == 0
    end

    debug(5) { "\nPass 3: abnormally short pulse followed by long pulses".green }
    loop do
      changes_made = 0
      (1..(fluxes.size - 2)).each do |i|
        if ((fluxes[i-1] > (sync_pulse_length * 1.5)) && (fluxes[i-1] < (sync_pulse_length * 1.8))) &&
           ((fluxes[i+1] > (sync_pulse_length * 1.5)) && (fluxes[i+1] < (sync_pulse_length * 1.8))) &&
           (fluxes[i] < sync_pulse_length) then
          changes_made += 1
          fluxes[i-1] -= 1
          fluxes[i] += 2
          fluxes[i+1] -= 1
        end
      end

      debug(5, newline: false) { "#{changes_made} ".white }
      break if changes_made == 0
    end

    debug(5) { "\nPass 4: abnormally short pulse followed by abnormally long pulse".green }
    loop do
      changes_made = 0
      (1..(fluxes.size - 2)).each do |i|
        if (fluxes[i - 1] < sync_pulse_length) && (fluxes[i] > 2 * sync_pulse_length) then
          changes_made += 1
          fluxes[i - 1] += 1
          fluxes[i] -= 1
        end
      end

      debug(5, newline: false) { "#{changes_made} ".white }
      break if changes_made == 0
    end

    debug(5) { "\nPass 5: abnormally long pulse followed by abnormally short pulse".green }
    loop do
      changes_made = 0
      (1..(fluxes.size - 2)).each do |i|
        if (fluxes[i + 1] < sync_pulse_length) && (fluxes[i] > 2 * sync_pulse_length) then
          changes_made += 1
          fluxes[i + 1] += 1
          fluxes[i] -= 1
        end
      end

      debug(5, newline: false) { "#{changes_made} ".white }
      break if changes_made == 0
    end

    debug(5) { "\nPass 6: 2.5x pulses".green }
    loop do
      changes_made = 0
      (1..(fluxes.size - 2)).each do |i|
        flux = fluxes[i]
        if (flux > (2.25 * sync_pulse_length)) && (flux < (3.25 * sync_pulse_length)) then
          fluxes.insert(i, 1.5 * sync_pulse_length)
          fluxes[i + 1] = flux - (1.5 * sync_pulse_length)
          changes_made = 1
        end
      end

      debug(5, newline: false) { "#{changes_made} ".white }
      break if changes_made == 0
    end

    self.force_sync_pulse_length = sync_pulse_length
  end

end

# track = MfmTrack.load("track001...trk")

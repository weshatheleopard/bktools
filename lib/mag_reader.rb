require 'wavefile'
require 'waveform_fixer'
require 'tape_splitter'

require 'term/ansicolor'
include Term::ANSIColor

class MagReader
  include WaveformFixer
  include TapeSplitter

  PILOT_LENGTH = 0o4000
  SPEEDTEST_LENGTH = 0o200

  CUTOFF_COEFF = 1.5   # Cycles longer than (base cycle length * CUTOFF_COEFF) will be
                       # considered to encode "1"s; shorter - "0"s.
  BIT_TOO_LONG = 3.1   # No bit cycle should be this long. Must be file format issue.

  attr_accessor :bk_file
attr_accessor :debug_bytes

  BUFFER_SIZE = 1024 * 1024

  def initialize(filename, debuglevel = 0)
    @buffer_start = 0
    @buffer_idx = nil

    @debuglevel = debuglevel
    @filename = filename # FIXME?
    @bk_file = BkFile.new
    @reader = WaveFile::Reader.new(@filename, WaveFile::Format.new(:mono, :pcm_16, 44100))
  end

  def debug(msg_level)
    return if msg_level > @debuglevel
    puts(yield)
  end

  def read_sample
    if @buffer_idx.nil? || (@buffer_idx >= BUFFER_SIZE) then
      @buffer_start = @reader.current_sample_frame
      @buffer_idx = 0
      @buffer = @reader.read(BUFFER_SIZE)
    end

    val = @buffer.samples[@buffer_idx]
    @buffer_idx += 1

    return val
  end

  def find_pilot
    val = -1
    count = 0
    prev_len = 0
    curr_len = 0

    PILOT_LENGTH.times do |i|
      while(val < 0) # Skip negative cycle
        val = read_sample
      end

      while(val >=0) do
        curr_len += 1
        val = read_sample
      end

      debug(20) { "   Pilot sequence: cycle # #{i}, cycle length = #{curr_len}, #{PILOT_LENGTH - i} cycles remaining" }

      if curr_len >= (prev_len - 2) then
        prev_len = curr_len
        curr_len = 0
      else
        debug(30) { "Pilot search failed @ #{@buffer_start + @buffer_idx}" }
        return false
      end
    end

    debug(5) { 'Pilot seqence found'.green }
    debug(7) { ' * '.blue.bold + "# of cycles seen      : #{PILOT_LENGTH.to_s.bold}" }
    return true
  end

  def perform_speedtest
    @total_speedtest_length = 0

    debug(10) { 'Starting speed test' }

    SPEEDTEST_LENGTH.times do
      @total_speedtest_length += read_period_with_sync
    end

    debug(5) { 'Speed test complete'.green }

    @length_of_0 = @total_speedtest_length / SPEEDTEST_LENGTH
    debug(15) { ' * '.blue.bold + "Cycles counted        : #{SPEEDTEST_LENGTH.to_s.bold}" }
    debug(15) { ' * '.blue.bold + "Total length          : #{@total_speedtest_length.to_s.bold}" }

    @cutoff = @length_of_0 * CUTOFF_COEFF

    debug(7) { ' * '.blue.bold + "Averaged '0' length   : #{@length_of_0.to_s.bold}" }
    debug(7) { ' * '.blue.bold + "'0'/'1' cutoff        : #{@cutoff.to_s.bold}" }
  end

  def read_period
    len = 0

    if @inv_phase then
      while(read_sample < 0) do
        len += 1
      end

      while(read_sample >= 0) do
        len += 1
      end
    else
      while(read_sample >= 0) do
        len += 1
      end

      while(read_sample < 0) do
        len += 1
      end
    end

    len
  end

  def read_period_with_sync  # same as PERIOD:
    read_period  # Skip sync
    read_period  # Read data
  end

  def detect_phase
    loop do
      pulse_len = nil

      pos_pulse_len = 0

      while(read_sample >= 0) do
        pos_pulse_len += 1
      end

      debug(30) { "Phase detection: positive pulse length = #{pos_pulse_len}, cutoff = #{@cutoff}  @ #{@buffer_start + @buffer_idx}" }

      if pos_pulse_len > @cutoff then
        @inv_phase = false
        pulse_len = pos_pulse_len
      else
        neg_pulse_len = 0

        while(read_sample < 0) do
          neg_pulse_len += 1
        end

        debug(30) { "Phase detection: negative pulse length = #{neg_pulse_len}, cutoff = #{@cutoff}  @ #{@buffer_start + @buffer_idx}" }

        if neg_pulse_len > @cutoff then
          @inv_phase = true
          pulse_len = neg_pulse_len
        end
      end

      if pulse_len then
        if (pulse_len > (@cutoff * 2)) then
          # Not a marker. start over.
          raise "Error finding file start marker"
        else
          debug(20) { "Phase indicator pulse found, length = #{pulse_len}, #{@inv_phase ? 'inverse' : 'straight' } phase" }
          debug(15) { 'Phase detection successful, starting speed test'.green }

          read_period_with_sync # Skip sync "1"

          return true
        end
      end
    end
  end

  def read_bit
    len = read_period_with_sync

    bit = (len > @cutoff)

    debug(20) { "   data cycle @ #{@buffer_start + @buffer_idx}, length = #{len}, cutoff = #{@cutoff}, bit = #{bit ? 1 : 0}" }

    bit
  end

  def read_bytes_without_marker(arr, len)
    len.times do |i|
      @byte = 0

      8.times do
        bit = read_bit
        @byte = (@byte >> 1) | ((bit) ? 128 : 0)
      end

      debug(10) { "--- byte #{Tools::octal(i + 1).bold} of #{Tools::octal(len).bold} read: #{Tools::octal_byte(@byte).yellow.bold}" } #(#{@byte.chr})" }

      arr << @byte
    end
  end

  def read_bytes_with_marker(arr, len)
    loop do
      pulse_len = 0
      if @inv_pase then
        while(read_sample < 0) do
          pulse_len += 1
        end
      else
        while(read_sample >= 0) do
          pulse_len += 1
        end
      end

      if pulse_len > @cutoff then
        if pulse_len > (2 * @cutoff) then
          raise "Error finding marker before data array"
        end

        debug(20) { "Array marker detected @ #{@buffer_start + @buffer_idx}" }

        read_period_with_sync # Skip sync "1"
        break
      end
    end

    read_bytes_without_marker(arr, len)
  end

  def read_header
    @header_array = []
    read_bytes_with_marker(@header_array, 20)

    @bk_file.start_address, @bk_file.length, @bk_file.name = @header_array.map{ |e| e.chr }.join.unpack("S<S<a16")

    debug(5) { "Header data read successfully".green }
    debug(7) { ' * '.blue.bold + "Start address : #{Tools::octal(@bk_file.start_address).bold}" }
    debug(7) { ' * '.blue.bold + "File length   : #{Tools::octal(@bk_file.length).bold}" }
    debug(7) { ' * '.blue.bold + 'File name     :' + '['.yellow + @bk_file.name.bold + ']'.yellow }
  end

  def read
    @inv_phase = false

    loop do #
      break if find_pilot
    end

    perform_speedtest
    detect_phase

    debug(5) { "Reading header..." }
    read_header

    debug(5) { "Reading data..." }
    read_bytes_with_marker(@bk_file.body, @bk_file.length)
    debug(5) { "Data read successfully".green }

    @checksum_array = []

    debug(5) { "Reading checksum..." }
    read_bytes_without_marker(@checksum_array, 2)

    @bk_file.checksum = Tools::bytes2word(*@checksum_array)

    debug(5) { "Checksum read successfully".green }
    debug(7) { ' * '.blue.bold + "File checksum     : #{Tools::octal(@bk_file.checksum).bold}" }
    debug(7) { ' * '.blue.bold + "Computed checksum : #{Tools::octal(@bk_file.compute_checksum).bold}" }

    debug(0) { "Verifying checksum: #{@bk_file.validate_checksum ? 'success'.green : 'failed'.red }" }
    debug(0) { "Read complete." }
  end



=begin
#puts @current_sample_pos if debug_bytes && debug_bytes.include?(@current_array.size)
    if len > (@length_of_0 * BIT_TOO_LONG) then
      puts "Bit WAY too long (#{len}) @ #{@current_sample_pos}, byte ##{@current_array.size}".red
      raise
    end

# if sync && bit == 1
        puts "Sync bit too long (#{len}) @ #{@current_sample_pos}, byte ##{@current_array.size}".red

debug(15) { "Processing block start marker: cycle ##{@marker_counter} @ #{@current_sample_pos}, imp_length=#{len}; lead_cycle_length=#{first_cycle}, expecting #{marker_body_length} cycles" }
raise "Marker final cycle not found (@ #{@current_sample_pos}); cycle #{len} long, expecting at least #{(@length_of_0 * 3)} long" if !ignore_errors
=end

end

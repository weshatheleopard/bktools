require 'wavefile'
require 'waveform_fixer'
require 'tape_splitter'
require 'help7'

require 'term/ansicolor'
include Term::ANSIColor

class MagReader
  include WaveformFixer
  include TapeSplitter
  include Help7

  PILOT_LENGTH = 0o2000  # ROM code has it at 0o4000, but in reality we can be less strict
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
    @reader = WaveFile::Reader.new(@filename, WaveFile::Format.new(:mono, :pcm_16, 44100))
  end

  def debug(msg_level)
    return if msg_level > @debuglevel
    msg = yield
    puts(msg) if msg
  end

  def read_sample
    if @buffer_idx.nil? || (@buffer_idx >= BUFFER_SIZE) then
      @buffer_start = @reader.current_sample_frame
      @buffer_idx = 0
      @buffer = @reader.read(BUFFER_SIZE)
    end

    val = @buffer.samples[@buffer_idx]

    raise EOFError if val.nil?

    @buffer_idx += 1

    return val
  end

  def current_sample_position
    @buffer_start + @buffer_idx
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
        debug(30) { "Pilot search failed @ #{current_sample_position}" }
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
      @total_speedtest_length += read_period_with_sync(:ignore_length_errors)
    end

    debug(5) { 'Speed test complete'.green }

    @length_of_0 = (@total_speedtest_length.to_f / SPEEDTEST_LENGTH).round(0)

    debug(15) { ' * '.blue.bold + "Cycles counted        : #{SPEEDTEST_LENGTH.to_s.bold}" }
    debug(15) { ' * '.blue.bold + "Total length          : #{@total_speedtest_length.to_s.bold}" }

    @cutoff = @length_of_0 * CUTOFF_COEFF

    debug(7) { ' * '.blue.bold + "Averaged '0' length   : #{@length_of_0.to_s.bold}" }
    debug(7) { ' * '.blue.bold + "'0'/'1' cutoff        : #{@cutoff.to_s.bold}" }
  end

  def read_period
    len1 = len2 = 0

    val = read_sample

    if @inv_phase then
      loop do
        val = read_sample
        break if val >= 0
        len1 += 1
      end

      loop do
        val = read_sample
        break if val < 0
        len2 += 1
      end
    else
      loop do
        val = read_sample
        break if val < 0
        len1 += 1
      end

      loop do
        val = read_sample
        break if val >= 0
        len2 += 1
      end
    end

    (len1 + len2)
  end

  def read_period_with_sync(ignore_length_errors = false)  # same as PERIOD:
    sync_len = read_period  # Skip sync

    if !ignore_length_errors && (sync_len > @cutoff) then
      array_position = ", byte ##{@current_array.size}" if @current_array

      debug(1) { "WARNING:".bold + " sync bit too long (#{sync_len}) @ #{current_sample_position}#{array_position}".red }
    end

    data_len = read_period  # Read data
    if !ignore_length_errors && (data_len > (@length_of_0 * BIT_TOO_LONG)) then
      array_position = ", byte ##{@current_array.size}" if @current_array

      debug(1) { "WARNING:".bold + " data bit too long (#{data_len}) @ #{current_sample_position}#{array_position}".red }
    end

    data_len
  end

  def detect_phase
    loop do
      pulse_len = nil

      pos_pulse_len = 0

      while(read_sample >= 0) do
        pos_pulse_len += 1
      end

      debug(30) { "Phase detection: positive pulse length = #{pos_pulse_len}, cutoff = #{@cutoff}  @ #{current_sample_position}" }

      if pos_pulse_len > @cutoff then
        @inv_phase = false
        pulse_len = pos_pulse_len
      else
        neg_pulse_len = 0

        while(read_sample < 0) do
          neg_pulse_len += 1
        end

        debug(30) { "Phase detection: negative pulse length = #{neg_pulse_len}, cutoff = #{@cutoff}  @ #{current_sample_position}" }

        if neg_pulse_len > @cutoff then
          @inv_phase = true
          pulse_len = neg_pulse_len
        end
      end

      if pulse_len then
        if (pulse_len > (@cutoff * 2)) then
          # Not a marker. start over.
          raise "Phase detection: pulse too long @ #{current_sample_position}"
        else
          debug(20) { "Phase indicator pulse found, length = #{pulse_len}, #{@inv_phase ? 'inverse' : 'straight' } phase" }
          debug(15) { 'Phase detection successful'.green }

          read_period_with_sync(:ignore_length_errors)  # Skip sync bits

          return true
        end
      end
    end
  end

  def read_bit
    len = read_period_with_sync

    bit = (len > @cutoff)

    debug(20) { "   data cycle @ #{current_sample_position}, length = #{len}, cutoff = #{@cutoff}, bit = #{bit ? 1 : 0}" }

    bit
  end

  def read_bytes_without_marker(arr, len)
    len.times do |i|
      byte = 0

      8.times do
        bit = read_bit
        byte = (byte >> 1) | ((bit) ? 128 : 0)
      end

      debug(10) { "--- byte #{Tools::octal(i + 1).bold} of #{Tools::octal(len).bold} read: #{Tools::octal_byte(byte).yellow.bold}" } #(#{byte.chr})" }

      arr << byte

#puts current_sample_position if debug_bytes && debug_bytes.include?(@current_array.size)

    end
  end

  def read_bytes_with_marker(arr, len)
    loop do
      pulse_len = 0
      if @inv_phase then
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
          raise "Marker too long before data array @ #{current_sample_position}"
        end

        debug(20) { "Data array marker detected @ #{current_sample_position}" }

        read_period_with_sync(:ignore_length_errors) # Skip sync bits
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
    @bk_file = BkFile.new
    @inv_phase = false

    loop do #
      break if find_pilot
    end

    perform_speedtest
    detect_phase

    debug(5) { "Reading header..." }
    read_header

    if (bk_file.name[13].ord == 38) then
      debug(2)  { "HELP7M file detected, proceeding to read".yellow }

      read_help7_body(Tools::bytes2word(bk_file.name.bytes[14], bk_file.name.bytes[15]))

      return
    end

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

end

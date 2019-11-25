require 'wavefile'
require 'waveform_fixer'
require 'tape_splitter'

require 'term/ansicolor'
include Term::ANSIColor

class MagReader
  include WaveformFixer
  include TapeSplitter

  CUTOFF_COEFF = 1.6   # Cycles longer than (base cycle length * CUTOFF_COEFF) will be
                       # considered to encode "1"s; shorter - "0"s.
  BIT_TOO_LONG = 2.9   # No bit cycle should be this long. Must be file format issue.

  attr_accessor :bk_file
  attr_accessor :invert_waveform
  attr_accessor :count_periods
attr_accessor :debug_bytes

  def initialize(filename, debuglevel = 0)
    @debuglevel = debuglevel
    @filename = filename
    @invert_waveform = false
    @bk_file = BkFile.new
    @count_periods = :both
  end

  def debug(msg_level)
    return if msg_level > @debuglevel
    puts(yield)
  end

  def read
    @current_sample_pos = 0
    @state = :find_pilot
    @pilot_cycles_counter = 0
    @total_pilot_length = 0
    @length_of_0 = @cutoff = nil
    @byte = 0
    @bit_counter = 0
    @reading_length = nil
    @byte_counter = 0
    @is_data_bit = true
    @marker_counter = nil
    @header_array = []
    @checksum_array = []
    @bk_file = BkFile.new

    current_cycle_state = nil
    previous_cycle_state = nil

    cycle_length = 0

    reader = WaveFile::Reader.new(@filename, WaveFile::Format.new(:mono, :pcm_16, 44100))
    reader.each_buffer(1024*1024) do |buffer|
      debug(5) { "Loaded #{buffer.samples.length.to_s.bold} samples" }

      buffer.samples.each { |c|
        current_cycle_state = (c < 0) ? :neg : :pos

        if current_cycle_state == previous_cycle_state then
          cycle_length += 1 if (@count_periods == :both) || (@count_periods == current_cycle_state)
        elsif (previous_cycle_state == :neg) && (current_cycle_state == :pos) then
          break if process_cycle(cycle_length)
          cycle_length = 1
        end

        previous_cycle_state = current_cycle_state
        @current_sample_pos += 1
      }
    end

    debug(0) { "Verifying checksum: #{@bk_file.validate_checksum ? 'success'.green : 'failed'.red }" }
    debug(0) { "Read complete." }
  end

  # Main read loop
  def process_cycle(len)
    case @state
    when :find_pilot then
      tpl = @total_pilot_length.to_f

      debug(20) { "   -pilot- cycle length = #{len}" }

      # If we read at least 200 pilot cycles by now and we encounter a cycle of length > 3.5 x '0',
      #    then it must be the end of the pilot.
      if (len > (tpl / @pilot_cycles_counter * 3)) && (@pilot_cycles_counter > 200) then
        @length_of_0 = (tpl / @pilot_cycles_counter).round(1)
        @cutoff = Integer((@length_of_0 * CUTOFF_COEFF).round(0))
        @state = :pilot_found
        debug(5) { 'Pilot seqence found'.green }
        debug(7) { ' * '.blue.bold + "# of cycles seen      : #{@pilot_cycles_counter.to_s.bold}" }
        debug(7) { ' * '.blue.bold + "Trailing cycle length : #{len.to_s.bold}" }
        debug(7) { ' * '.blue.bold + "Averaged '0' length   : #{@length_of_0.to_s.bold}" }
        debug(7) { ' * '.blue.bold + "'0'/'1' cutoff        : #{@cutoff.to_s.bold}" }
      else
        @total_pilot_length += len
        @pilot_cycles_counter += 1
        debug(40) { "Pilot sequence: cycle ##{@pilot_cycles_counter}, cycle length = #{len}, total cycles = #{@total_pilot_length}" }
      end
    when :pilot_found then
      debug(15) { "Synchro '1' after pilot: (#{(len > @cutoff) ? 'success'.green : 'failed'.red })" }
      @state = :pilot_found2
    when :pilot_found2 then
      debug(15) { "Synchro '0' after pilot: (#{(len < @cutoff) ? 'success'.green : 'failed'.red })" }
      @state = :header_marker
      start_marker
    when :header_marker
      if read_marker(len) then
        @is_data_bit = true
        @current_array = @header_array
        @reading_length = @byte_counter = 20
        debug(5) { "Reading file header..." }
        @state = :read_header
      end
    when :read_header then
      if read_bit(len) then
        start_marker
        @bk_file.start_address, @bk_file.length, @bk_file.name = @header_array.map{ |e| e.chr }.join.unpack("S<S<a16")
        debug(5) { "Header data read successfully".green }
        debug(7) { ' * '.blue.bold + "Start address : #{Tools::octal(@bk_file.start_address).bold}" }
        debug(7) { ' * '.blue.bold + "File length   : #{Tools::octal(@bk_file.length).bold}" }
        debug(7) { ' * '.blue.bold + 'File name     :' + '['.yellow + @bk_file.name.bold + ']'.yellow }
        @state = :body_marker
      end
    when :body_marker
      if read_marker(len) then
        @is_data_bit = true
        @current_array = @bk_file.body
        @reading_length = @byte_counter = @bk_file.length
        debug(5) { "Reading file body..." }
        @state = :read_data
      end
    when :read_data
      debug(20) { "      -data- #{@is_data_bit ? 'data' : 'sync' } cycle length = #{len}" }
      if read_bit(len) then
        @is_data_bit = true
        @current_array = @checksum_array
        @reading_length = @byte_counter = 2
        debug(5) { "Reading checksum..." }
        @state = :cksum
      end
    when :cksum
      debug(20) { "      -checksum- #{@is_data_bit ? 'data' : 'sync' } cycle length = #{len}" }
      if read_bit(len) then
        @bk_file.checksum = Tools::bytes2word(*@checksum_array)
        debug(5) { "Checksum read successfully".green }
        debug(7) { ' * '.blue.bold + "File checksum     : #{Tools::octal(@bk_file.checksum).bold}" }
        debug(7) { ' * '.blue.bold + "Computed checksum : #{Tools::octal(@bk_file.compute_checksum).bold}" }
        start_marker
        @state = :end_trailer
      end
    when :end_trailer then
      # Trailing marker's lead length is equal to the length of at least 9 "0" cycles.
      if read_marker(len, 256, 9, :ignore_errors) then
        debug(5) { "Read completed successfully.".green }
        return true
      end
    end

    false
  end

  def start_marker
    @marker_counter = 0
    @marker_state = :marker_lead
  end
  private :start_marker

  def read_bit(len)
    bit = (len > @cutoff) ? 1 : 0

puts @current_sample_pos if debug_bytes && debug_bytes.include?(@current_array.size)
    if len > (@length_of_0 * BIT_TOO_LONG) then
      puts "Bit WAY too long (#{len}) @ #{@current_sample_pos}, byte ##{@current_array.size}".red
      raise
    end

    if @is_data_bit then
      debug(15) { "   bit ##{@bit_counter} read: #{bit}" }

      @byte = (@byte >> 1) | ((bit == 1) ? 128 : 0)
      @bit_counter += 1
      if @bit_counter == 8 then
        @current_array << @byte
        @byte_counter -= 1

        @bit_counter = 0
        debug(10) { "--- byte #{Tools::octal(@reading_length - @byte_counter).bold} of #{Tools::octal(@reading_length).bold} read: #{Tools::octal_byte(@byte).yellow.bold}" } #(#{@byte.chr})" }
        @byte = 0
      end
    else # sync bit
      if bit == 1
        puts "Sync bit too long (#{len}) @ #{@current_sample_pos}, byte ##{@current_array.size}".red
        raise
      end
      return true if @byte_counter == 0
    end

    @is_data_bit = !@is_data_bit

    return false
  end

  def read_marker(len, marker_body_length = 8, first_cycle = nil, ignore_errors = false)
    debug(15) { "Processing block start marker: cycle ##{@marker_counter} @ #{@current_sample_pos}, imp_length=#{len}; lead_cycle_length=#{first_cycle}, expecting #{marker_body_length} cycles" }

    case @marker_state
    when :marker_lead then # Marker lead impulse
      if first_cycle && (len < ((first_cycle - 0.5) * @length_of_0)) then
        raise "Lead cycle too short " if !ignore_errors
      end
      @marker_counter = 0
      @marker_state = :marker_body
    when :marker_body then
      if (@marker_counter > 2) && (len > @cutoff) then
        if (len < (@length_of_0 * 3)) then
          raise "Marker final cycle not found (@ #{@current_sample_pos}); cycle #{len} long, expecting at least #{(@length_of_0 * 3)} long" if !ignore_errors
        end
        @marker_state = :post_marker_1
      end
    when :post_marker_1 then
      raise "Sync '1' after marker not found (@ #{@current_sample_pos})" if !ignore_errors && (len < @cutoff)
      @marker_state = :post_marker_0
    when :post_marker_0 then
      if !ignore_errors then
        raise "Sync '0' after marker not found (@ #{@current_sample_pos})"  if len > @cutoff
        raise "Marker too short" if @marker_counter < (marker_body_length + 2)
      end

      return true
    end

    @marker_counter +=1
    return false
  end

end

require "wavefile"

class MagRead
  CUTOFF_COEFF = 1.7  # Impulses longer than (base impulse length * CUTOFF_COEFF) will be
                      # considered to encode "1"sl; shorter - "0"s.
  include WaveFile

  def initialize(filename, debuglevel = false)

    reader = Reader.new(filename, Format.new(:mono, :pcm_16, 44100)).each_buffer(1024*1024*1024) do |buffer|
      @buffer = buffer
      puts "Read #{buffer.samples.length} sample frames."
    end

    @debuglevel = debuglevel
  end

  def debug(msg_level, msg)
    puts msg if msg_level <= @debuglevel
  end

  def convert_file_to_legths
    position_in_file = 0
    @hash = {}

    counter = 0

    @buffer.samples.each { |c|
      position_in_file += 1
      if c > 0 then
        counter += 1
      else
        if counter != 0 then
          @hash[position_in_file] = counter
          counter = 0
        end
      end
    }

  end

  def start_marker
    @marker_counter = 0
  end
  private :start_marker
  
  def read
    convert_file_to_legths if @hash.nil?

    state = :find_pilot
    pilot_counter = 0
    total_pilot_length = 0
    @impulse_length = @cutoff = nil
    @byte = 0
    @bit_counter = 0
    @reading_length = nil
    @byte_counter = 0
    @is_data_bit = true
    @marker_counter = nil
    @header_array = []
    @body_array = []
    @checksum_array = []
    @checksum = nil

    @hash.each_pair { |position, len|
      @current_position = position

      case state
      when :find_pilot then
        tpl = total_pilot_length.to_f

        debug 20, "   -pilot- impulse length --> #{len}"

        if (pilot_counter > 200) && (len > (tpl / pilot_counter * 3.5)) then
          state = :pilot_found
          @impulse_length = (tpl / pilot_counter)
          @cutoff = (@impulse_length * CUTOFF_COEFF)
          debug 5, "Pilot seqence found (final impulse length = #{len}), impulse count = #{pilot_counter}, 0/1 averaged length = #{@impulse_length}, cutoff = #{@cutoff}"
        else
          total_pilot_length += len
          pilot_counter += 1
          debug 40, "Pilot impulse ##{pilot_counter}, impulse length: #{len}, total sequence length = #{total_pilot_length}"
        end
      when :pilot_found then
        debug 15, "Synchro '1' after pilot: (#{(len > @cutoff) ? 'success' : 'fail' })"
        state = :pilot_found2
      when :pilot_found2 then
        debug 15, "Synchro '0' after pilot: (#{(len < @cutoff) ? 'success' : 'fail' })"
        state = :header_marker
        start_marker
      when :header_marker
        if read_marker(len) then
          @is_data_bit = true
          @current_array = @header_array
          @reading_length = @byte_counter = 20
          debug 5, "Reading file header..."
          state = :read_header
        end
      when :read_header then
        if read_bit(len) then
          start_marker
          @addr, @len, @name = @header_array.map{ |e| e.chr }.join.unpack("S<S<a16")
          debug 5, "   Header read: addr=#{octal(@addr)}, length=#{octal(@len)}, name=#{@name}" 
          state = :body_marker
        end
      when :body_marker
        if read_marker(len) then
          @is_data_bit = true
          @current_array = @body_array
          @reading_length = @byte_counter = @len
          debug 5, "Reading file body..."
          state = :read_data
        end
      when :read_data
        debug 20, "      -data- #{@is_data_bit ? 'data' : 'sync' } impulse length --> #{len}"
        if read_bit(len) then
          @is_data_bit = true
          @current_array = @checksum_array
          @reading_length = @byte_counter = 2
          debug 5, "Reading checksum..."
          state = :cksum
        end
      when :cksum
        debug 20, "      -checksum- #{@is_data_bit ? 'data' : 'sync' } impulse length --> #{len}"
        if read_bit(len) then
          @checksum = bytes2word(*@checksum_array)
          debug 5, "Checksum read = #{octal(@checksum)}, computed checksum = #{octal(compute_checksum)}"
          start_marker
          state = :end_trailer
        end
      when :end_trailer then
        # Trailing marker's lead length is equal to the length of at least 9 "0" impulses.
        if read_marker(len, 256, 9, :ignore_errors) then
          debug 5, "Read completed successfully"
          debug 0, "Checksum validation: #{(@checksum == compute_checksum) ? 'success!' : 'FAIL' }"
          break
        end
      end
    }  ;1

  end

  def read_bit(len)
    bit = (len > @cutoff) ? 1 : 0

    raise "Bit WAY too long (#{len}) @ #{@current_position}, byte ##{@current_array.size}}" if len > (@impulse_length * 2.8)    

    if @is_data_bit then
      debug 15, "   bit ##{@bit_counter} read: #{bit}"

      @byte = (@byte >> 1) | ((bit == 1) ? 128 : 0)
      @bit_counter += 1
      if @bit_counter == 8 then
        @current_array << @byte
        @byte_counter -= 1

        @bit_counter = 0
        debug 10, "--- byte #{octal(@reading_length - @byte_counter)} of #{octal(@reading_length)} read: #{@byte.to_s(8)}" #(#{@byte.chr})"
        @byte = 0
      end
    else # sync bit
      if bit == 1
        raise "Sync bit too long (#{len}) @ #{@current_position}, byte ##{@len - @byte_counter}" 
      end
      return true if @byte_counter == 0
    end

    @is_data_bit = !@is_data_bit

    return false
  end

  def read_marker(len, marker_len = 8, first_impulse = nil, ignore_errors = false)
    debug 15, "Processing block start marker: impulse ##{@marker_counter}, imp_length=#{len}; lead_impulse_length=#{first_impulse}, expecting #{marker_len} impulses"

    case @marker_counter
    when 0 then
      raise "Lead impulse too short " if !ignore_errors && first_impulse && (len < ((first_impulse - 0.5) * @impulse_length))
    when marker_len then
      raise "Marker final impulse not found" if !ignore_errors && (len < (@impulse_length * 3.5))
    when marker_len + 1 then
      raise "Sync '1' after marker not found" if !ignore_errors && len < @cutoff
    when marker_len + 2 then
      raise "Sync '0' after marker not found" if !ignore_errors && len > @cutoff
      return true
    end
    @marker_counter +=1
    return false
  end

  def compute_checksum
    cksum = 0
    @body_array.each { |byte|
      cksum += byte
      if cksum > 0o177777 then
        cksum = cksum - 0o200000 + 1 # 16-bit cutoff + ADC
      end
    }
    cksum
  end

=begin
  def bytes2words
    word_array = []

    arr = @body_array.dup
    sz = arr.size
    sz += 1 if sz.odd?
    sz = sz / 2

    sz.times do
      b0 = arr.shift
      b1 = arr.shift || 0
      bb = bytes2word(b0, b1)
      word_array << octal(bb)
    end
    word_array
  end
=end

  def bytes2word(b0, b1)
    (b1 << 8) | b0
  end
       
  def octal(bb)
    ('000000' + bb.to_s(8))[-6..-1]
  end

#class MagRead
  def print_file
    puts @name
    puts @len
    
    count = 0
    b0 = b1 = nil
    str = ''

    @len.times do |i|
      c = @body_array[i]

      if b0.nil? then
        b0 = c
      else
        b1 = c
      end

      c = '.' if c < 32 
      str << c    

      if (count % 8) == 0 then
        print str, "\n", octal(@addr + count), ": "
        str = ''
      end


      if b0 && b1 then
        print octal(bytes2word(b0, b1)), " "
        b0 = b1 = nil
      end
      
      count += 1

    end

    puts    
   
    # Mind the odd start address... there are some quirks there. But, doesnt matter ATM   
#    sz.times do |i|
 #     puts "#{}: #{}"
  #    current_address += 2
   # end
    # Mind odd lengths    

  end
    
end

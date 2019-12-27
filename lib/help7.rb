module Help7

  def read_semiperiod
    len = 0

    if @inv_phase then
      loop do
        val = read_sample
        break if val >= 0
        len += 1
      end
    else
      loop do
        val = read_sample
        break if val < 0
        len += 1
      end
    end

    len
  end

  def read_block_marker
puts "--------------entering MRKR @ #{current_sample_position}"
    pre_marker = false

    loop do
      if pre_marker then
        read_period # Skip a period
        len = read_period
puts "===> looking for LONG marker @ #{current_sample_position}, len=#{len}, need > #{4.5 * @length_of_0} < #{8 * @length_of_0} "
        if (len > 4.5 * @length_of_0) && (len < 8 * @length_of_0) then  # The code says 7.5 not 8 but OK for now
          puts "MRKR: found LONG marker @ #{current_sample_position}"
          break
        else
          pre_marker = false
        end
      else
        len = read_period
        if (len > @cutoff) && (len <= 2 * @cutoff) then
          puts "MRKR: found short marker @ #{current_sample_position}"
          pre_marker = true
        end
      end
    end
puts "--------------leaving MRKR @ #{current_sample_position}"
  end

  def read_block_header(arr, arr_len)
    loop do
      len = read_semiperiod # Note we are reading SEMIperiod here

      if (len > @cutoff) && (len < 2 * @cutoff) then

        # Pilot bits are done
        debug(10) { "Block header marker found @".green + current_sample_position.to_s.bold }

# Prolly need to skip the rest of semiperiod here

        break
      end
    end
    read_period_with_sync # Skip sync
#!!! NOTE: when I fix the semiperiod above, need to change this to jst "read_period"

    read_bytes_without_marker(arr, arr_len)
  end

  def read_help7_body
    @help7_checksum_array = []

    read_block_header(@help7_checksum_array, 2)    

    @bk_file.checksum = Tools::bytes2word(*@help7_checksum_array)
    debug(5) { "Checksum read successfully".green }
    debug(7) { ' * '.blue.bold + "File checksum     : #{Tools::octal(@bk_file.checksum).bold}" }

    @cutoff2 = @length_of_0 * 2.5 + 2
    @cutoff3 = @length_of_0 * 3.5 + 2

    read_block_marker

# -----search for block
    @block_header_array = []
    read_block_header(@block_header_array, 4)

    this_block_nibbles = @block_header_array[0] # The byte encodes which 2 bits a particular length pulse encodes in this block
    # Nibbles correspond to periods measured in length of period of sync tone: 

    # byte: 76543210
    #       |||||||+---       < 1.5 of sync tone period, most significant bit
    #       ||||||+----       < 1.5 of sync tone period, least significant bit
    #       |||||+----- 1.5 ... 2.5 of sync tone period, most significant bit 
    #       ||||+------ 1.5 ... 2.5 of sync tone period, least significant bit
    #       |||+------- 2.5 ... 3.5 of sync tone period, most significant bit 
    #       ||+-------- 2.5 ... 3.5 of sync tone period, least significant bit
    #       |+---------       > 3.5 of sync tone period, most significant bit
    #       +----------       > 3.5 of sync tone period, least significant bit

    block_checksum = Tools::bytes2word(@block_header_array[2], @block_header_array[3])

    debug(10) { "Block header read successfully".green }
    debug(15) { ' * '.blue.bold + "Pulse length to nibbles mapping : " + this_block_nibbles.to_s(2).bold }
    debug(15) { ' * '.blue.bold + "Block number                    : " + Tools::octal(@block_header_array[1]).bold }
    debug(15) { ' * '.blue.bold + "Block checksum                  : " + Tools::octal(block_checksum).bold }

    @current_block_length = @block_length  # This is not true for the last block, but we'll fix that later

    loop do # Find block data start marker
      len = read_semiperiod
      
      puts "#{len} @ #{current_sample_position}"
       if (len > @cutoff) && (len < (2 * @cutoff)) then  # Marker found!
        break
      else
        # TODO: return to the block search loop
      end
    end

    debug(10) { "Block data header found" }

    read_period_with_sync
    read_period

    byte = 0

    block = []
    
    @current_block_length.times { |byte_no|
      byte = 0
      debug(30) { "0----|%4.1f|--1--|%4.1f|--2--|%4.1f|----3" % [@cutoff, @cutoff2, @cutoff3] }

      # Read a byte
      4.times do
        len = read_period

        case 
        when len < @cutoff then
          nibble = this_block_nibbles & 3
          debug(30) { "^                                      (#{len} @ #{current_sample_position})" }
        when len < @cutoff2 then
          nibble = (this_block_nibbles & 014) >> 2
          debug(30) { "             ^                         (#{len} @ #{current_sample_position})" }
        when len < @cutoff3 then
          nibble = (this_block_nibbles & 060) >> 4
          debug(30) { "                        ^              (#{len} @ #{current_sample_position})" }
        else
          nibble = (this_block_nibbles & 0300) >> 6
          debug(30) { "                                     ^ (#{len} @ #{current_sample_position})" }
        end

        byte = byte >> 1
        byte = byte | 0200 if (nibble & 2) != 0

        byte = byte >> 1
        byte = byte | 0200 if (nibble & 1) != 0
      end

      debug(15) { "Byte read: #{Tools::octal(byte).to_s.bold}" }

      block << byte
    }

    puts "end of bytes in block @ #{current_sample_position}"

    computed_block_checksum = Tools::checksum(block) + @bk_file.checksum

    debug(7) { ' * '.blue.bold + "Computed block checksum : #{Tools::octal(computed_block_checksum).bold}" }

    debug(5) { "Verifying block checksum: #{(computed_block_checksum == block_checksum) ? 'success'.green : 'failed'.red }" }

    return

  end

end

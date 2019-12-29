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
    pre_marker = false

    loop do
      if pre_marker then
        read_period # Skip a period
        len = read_period
puts "===> looking for LONG marker @ #{current_sample_position}, len=#{len}, need > #{@cutoff3} and < #{@marker_cutoff} "
        if (len > 4.5 * @length_of_0) #&& (len < @marker_cutoff) then  # The code says 7.5 but tapes beg to differ
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

  def compute_cutoffs
    @cutoff  = @total_speedtest_length * 1.5
    @cutoff2 = @total_speedtest_length * 3.0
    @cutoff3 = @total_speedtest_length * 4.5

    @marker_cutoff = (((@cutoff2 + @cutoff3) / MagReader::SPEEDTEST_LENGTH) + 8).to_i + 2
    @cutoff  = (@cutoff  / MagReader::SPEEDTEST_LENGTH).to_i + 2
    @cutoff2 = (@cutoff2 / MagReader::SPEEDTEST_LENGTH).to_i + 2
    @cutoff3 = (@cutoff3 / MagReader::SPEEDTEST_LENGTH).to_i + 2
  end

  def read_help7_body
    @help7_checksum_array = []

    read_block_header(@help7_checksum_array, 2)

    @bk_file.checksum = Tools::bytes2word(*@help7_checksum_array)
    debug(5) { "Checksum read successfully".green }
    debug(7) { ' * '.blue.bold + "File checksum     : #{Tools::octal(@bk_file.checksum).bold}" }

    compute_cutoffs

    read_help7_block

  end


  def read_help7_block
    @block_header_array = []

    read_block_marker

    read_block_header(@block_header_array, 4)

    # The byte encodes which 2 bits pulse of a particular length
    this_block_nibbles = @block_header_array[0]  #  encodes in this block

    # Nibbles correspond to periods measured in length of a period of the pilot tone:

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

#      puts "#{len} @ #{current_sample_position}"
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

    @current_block_length.times { |i|
      byte = 0
      debug(30) { '   ' + '-' * (@cutoff.to_i - 1) + '|' + '-' * (@cutoff2 - @cutoff - 1).to_i + '|' + '-' * (@cutoff3 - @cutoff2 - 1).to_i + '|' + '-----------------' }

      # Read a byte
      4.times do
        len = read_period

        debug(30) { ("%3d" % [ len ] ) + ('=' * len) }

        case
        when len <= @cutoff then
          nibble = this_block_nibbles & 3
        when len <= @cutoff2 then
          nibble = (this_block_nibbles & 014) >> 2
        when len <= @cutoff3 then
          nibble = (this_block_nibbles & 060) >> 4
        else
          nibble = (this_block_nibbles & 0300) >> 6
        end

        byte = byte >> 1
        byte = byte | 0200 if (nibble & 2) != 0

        byte = byte >> 1
        byte = byte | 0200 if (nibble & 1) != 0
      end

      debug(10) { "--- byte #{Tools::octal(i + 1).bold} of #{Tools::octal(@current_block_length).bold} read: #{Tools::octal_byte(byte).yellow.bold}" } #(#{@byte.chr})" }

      block << byte
    }

    debug(20) { "End of block @ #{current_sample_position}" }

    computed_block_checksum = Tools::checksum(block) + @bk_file.checksum

    debug(7) { ' * '.blue.bold + "Computed block checksum : #{Tools::octal(computed_block_checksum).bold}" }
    debug(7) { ' * '.blue.bold + "Read block checksum     : #{Tools::octal(block_checksum).bold}" }

    debug(5) { "Verifying block checksum: #{(computed_block_checksum == block_checksum) ? 'success'.green : 'failed'.red }" }
  end

end

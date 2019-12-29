require 'help7_block'

module Help7
  def read_semiperiod(phase = @inv_phase)
    len = 0

    if phase then
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

  def find_block_marker
    pre_marker = false

    loop {
      if pre_marker then
        read_period # Skip a period

        len = read_period

        debug(30) { "Looking for LONG marker @ #{current_sample_position}, len=#{len}, need > #{@cutoff3} and < #{@marker_cutoff}" }

        if (len > @cutoff3) && (len < @marker_cutoff) then
          debug(30) { "--- Found LONG marker @".green + current_sample_position.to_s.bold }
          break
        else
          pre_marker = false
        end
      else
        len = read_period
        if (len > @cutoff) && (len <= 2 * @cutoff) then
          debug(30) { "--- Found short marker @".green + current_sample_position.to_s.bold }
          pre_marker = true
        end
      end
    }
  end

  def read_block_header(arr, arr_len)
    loop do
      len = read_semiperiod # Note we are reading SEMIperiod here

      if (len > @cutoff) && (len < 2 * @cutoff) then
        # Pilot bits are done
        debug(10) { "Block header marker found @".green + current_sample_position.to_s.bold }

        read_semiperiod(!@inv_phase) # Skip the rest of period
        break
      end
    end

    read_period  # Skip period

    read_bytes_without_marker(arr, arr_len)
  end

  def compute_cutoffs
    @cutoff  = @total_speedtest_length * 1.5
    @cutoff2 = @total_speedtest_length * 3.0
    @cutoff3 = @total_speedtest_length * 4.5

    @marker_cutoff = (((@cutoff2 + @cutoff3) / MagReader::SPEEDTEST_LENGTH) + 8).to_i + 3
    @cutoff  = (@cutoff  / MagReader::SPEEDTEST_LENGTH).to_i + 3
    @cutoff2 = (@cutoff2 / MagReader::SPEEDTEST_LENGTH).to_i + 3
    @cutoff3 = (@cutoff3 / MagReader::SPEEDTEST_LENGTH).to_i + 3
  end

  def read_help7_body(block_length)
    debug(7) { ' * '.blue.bold + "HELP7M block length = #{Tools::octal(block_length)}".yellow }

    @help7_checksum_array = []

    read_block_header(@help7_checksum_array, 2)

    @bk_file.checksum = Tools::bytes2word(*@help7_checksum_array)
    debug(5) { "Checksum read successfully".green }
    debug(7) { ' * '.blue.bold + "File checksum     : #{Tools::octal(@bk_file.checksum).bold}" }

    compute_cutoffs

    bytes_remaining = @bk_file.length
    read_blocks = Array.new(((@bk_file.length - 1).divmod(block_length).first + 1))

    loop {
      find_block_marker

      current_block = Help7Block.new

      current_block.length = [ block_length, bytes_remaining ].min

      if block = read_help7_block(current_block) then
        block_address = (block.number - 1) * block_length

        if read_blocks[block.number - 1] != true then
          block.length.times { |i|
            @bk_file.body[block_address + i] = block.body[i]
          }

          bytes_remaining -= block.length
          read_blocks[block.number - 1] = true

          debug(7) { "Blocks remaining to read: " + read_blocks.collect { |f| f ? '+' : '-' }.join }
          debug(7) { "Bytes remaining to read:  " + bytes_remaining.to_s.bold }

        else 
          debug(7) { "Block already read. Bytes remaining to read: " + bytes_remaining.to_s.bold }
        end

        if bytes_remaining == 0 then
          debug(0) { "Verifying file checksum: #{@bk_file.validate_checksum ? 'success'.green : 'failed'.red }" }
          break
        end

      end
    }
  end

  def read_help7_block(current_block)
    block_header_array = []

    read_block_header(block_header_array, 4)

    # The byte encodes which 2 bits pulse of a particular length
    this_block_nibbles = block_header_array[0]  #  encodes in this block

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

    current_block.owner_file_checksum = @bk_file.checksum
    current_block.checksum = Tools::bytes2word(block_header_array[2], block_header_array[3])
    current_block.number = block_header_array[1] # 1-based

    debug(10) { "Block header read successfully".green }
    debug(15) { ' * '.blue.bold + "Pulse length to nibbles mapping : " + this_block_nibbles.to_s(2).bold }
    debug(15) { ' * '.blue.bold + "Block number                    : " + current_block.number.to_s.bold }
    debug(15) { ' * '.blue.bold + "Block checksum                  : " + Tools::octal(current_block.checksum).bold }

    loop do # Find block data start marker

      len = read_semiperiod
      read_semiperiod(!@inv_phase)

      if (len > @cutoff) && (len < (2 * @cutoff)) then  # Marker found!
        break
      else
        # TODO: resume block search
      end
    end

    debug(10) { "Found block data header" }

    read_period
    read_period

    byte = 0

    current_block.length.times { |i|
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

      debug(10) { "--- byte #{Tools::octal(i + 1).bold} of #{Tools::octal(current_block.length).bold} read: #{Tools::octal_byte(byte).yellow.bold}" } #(#{@byte.chr})" }

      current_block.body << byte
    }

    debug(20) { "End of block @ #{current_sample_position}" }

    debug(7) { ' * '.blue.bold + "Computed block checksum : #{Tools::octal(current_block.compute_checksum + current_block.owner_file_checksum).bold}" }
    debug(7) { ' * '.blue.bold + "Read block checksum     : #{Tools::octal(current_block.checksum).bold}" }

    debug(5) { "Verifying block #{current_block.number} checksum: #{current_block.validate_checksum ? 'success'.green : 'failed'.red }" }

    if current_block.validate_checksum then
      return current_block
    else
      return nil
    end
  end

end

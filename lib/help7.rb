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

    loop do
      if pre_marker then
        len = read_period

        debug(30) { if len > 0 then
                      "Looking for LONG marker @ #{current_sample_position}, len=#{len}, need > #{@const50} and <= #{@const50 + @const25}"
                    else nil
                    end }

        if (len > @const50) && (len <= (@const50 + @const25)) then
          debug(30) { "--- Found LONG marker @".green + current_sample_position.to_s.bold }
          break
        else
          pre_marker = false
        end
      else
        len = read_semiperiod
        debug(30) { if len > 0 then
                      "Looking for short marker @ #{current_sample_position}, len=#{len}, need > #{@cutoff} and <= #{2 * @cutoff}"
                    else nil
                    end }

        if (len > @cutoff) && (len <= 2 * @cutoff) then
          debug(30) { "--- Found short marker @".green + current_sample_position.to_s.bold }

          read_semiperiod(!@inv_phase) # Skip 2nd half
          read_period  # Skip a period
          read_period  # Skip a period
          pre_marker = true
        end
      end
    end
  end

  def read_block_header(arr, arr_len)
    loop do
      len = read_semiperiod # Note we are reading SEMIperiod here

      debug(30) { if len > 0 then
                    "Looking for block header marker @ #{current_sample_position}, len=#{len}, need > #{@cutoff} and <= #{2 * @cutoff}"
                  else nil
                  end }

      if (len > @cutoff) && (len <= (2 * @cutoff)) then
        # Pilot bits are done
        debug(10) { "Block header marker found @ ".green + current_sample_position.to_s.bold }

        read_semiperiod(!@inv_phase) # Skip the rest of period
        break
      end
    end

    read_period  # Skip period

    debug(11) { "Reading block header data starting @ ".green + current_sample_position.to_s.bold }
    read_bytes_without_marker(arr, arr_len)
  end

  def compute_cutoffs
    @cutoff  = (@total_speedtest_length * 1.5)
    @cutoff1 = (@total_speedtest_length * 1.5)
    @const25 = (@total_speedtest_length * 2.5)
    @const35 = (@total_speedtest_length * 3.5)
    @const50 = @const25 + @const35

    @cutoff  = (@cutoff  / MagReader::SPEEDTEST_LENGTH).floor
    @cutoff1 = (@cutoff1 / MagReader::SPEEDTEST_LENGTH * 1.35).floor
    @const25 = (@const25 / MagReader::SPEEDTEST_LENGTH * 1.35).floor
    @const35 = (@const35 / MagReader::SPEEDTEST_LENGTH * 1.35).floor
    @const50 = (@const50 / MagReader::SPEEDTEST_LENGTH * 1.2).floor  # was 1.35

    # Compensation for high-speed mode
    if @total_speedtest_length < (MagReader::SPEEDTEST_LENGTH * 7) then
      @cutoff1 += 4
      @const25 += 4
      @const35 += 4
    end

  end

  def read_help7_body(block_length)
    @block_length = block_length
    debug(7) { ' * '.blue.bold + "HELP7M block length = #{Tools::octal(block_length)}".yellow }

    @help7_checksum_array = []

    read_block_header(@help7_checksum_array, 2)

    @bk_file.checksum = Tools::bytes2word(*@help7_checksum_array)
    debug(5) { "Checksum read successfully".green }
    debug(7) { ' * '.blue.bold + "File checksum     : #{Tools::octal(@bk_file.checksum).bold}" }

    compute_cutoffs

    bytes_remaining = @bk_file.length
    @num_of_blocks = ((@bk_file.length - 1).divmod(block_length).first + 1)
    read_blocks = Array.new(@num_of_blocks)

    loop {
      find_block_marker

      current_block = Help7Block.new

      if block = read_help7_block(current_block) then
        block_address = (block.number - 1) * block_length

        if read_blocks[block.number - 1] != true then
          block.length.times { |i|
            @bk_file.body[block_address + i] = block.body[i]
          }

          bytes_remaining -= block.length
          read_blocks[block.number - 1] = true

          debug(6) { "Blocks remaining to read: " + read_blocks.collect { |f| f ? '+'.green : '-'.red }.join }
          debug(7) { "Bytes remaining to read:  " + bytes_remaining.to_s.bold }
        else
          debug(7) { "Block already read. Bytes remaining to read: " + bytes_remaining.to_s.bold }
        end

        break if bytes_remaining == 0
      end
    }
  end

  def read_help7_block(current_block)
    block_header_array = []

    read_block_header(block_header_array, 4)

    # The byte denotes which 2 bits a pulse of a particular length encodes in this block
    this_block_nibbles = block_header_array[0]
    nibbles = [ (this_block_nibbles & 3),
                (this_block_nibbles & 014) >> 2,
                (this_block_nibbles & 060) >> 4,
                (this_block_nibbles & 0300) >> 6 ]

    # Nibbles that correspond to a period (measured in length of a period of the pilot tone):

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

    current_block.length =
      if current_block.number == @num_of_blocks then # Last block may be shorter than others
        @bk_file.length - ((@num_of_blocks - 1) * @block_length)
      else @block_length
      end

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

    debug(10) { "Found block data header @ ".green + current_sample_position.to_s.bold }

    read_period
    read_period

    byte = 0

    current_block.length.times { |i|
      byte = 0
      debug(30) {
        @max_cols = ENV['COLUMNS'].to_i
        @max_cols = 80 if @max_cols < 80

        '                ' + '-' * (@cutoff1.to_i - 1) + '>' + '-' * (@const25 - @cutoff1 - 1).to_i + '>' + '-' * (@const35 - @const25 - 1).to_i + '>' + '-----------------'
      }

      # Read a byte
      4.times do
        len = read_period

        nibble_idx = case
                     when len > @const35 then 3
                     when len > @const25 then 2
                     when len > @cutoff1 then 1
                     else 0
                     end

        nibble = nibbles[nibble_idx]

        debug(30) { meter = ('=' * len)
                    meter = case nibble_idx
                            when 0 then meter.green
                            when 1 then meter.blue
                            when 2 then meter.yellow
                            when 3 then meter.red
                            end

                   ("%10u %1u %3u" % [ current_sample_position, nibble, len ]).bold + meter }

        byte = byte >> 1
        byte = byte | 0200 if (nibble & 2) != 0

        byte = byte >> 1
        byte = byte | 0200 if (nibble & 1) != 0
      end

      debug(14) {
        ch = if byte > 31 then "(#{byte.chr})" else '' end

        "--- byte #{Tools::octal(i + 1).bold} of #{Tools::octal(current_block.length).bold} read: #{Tools::octal_byte(byte).yellow.bold} #{ch}" }

      current_block.body << byte
    }

    debug(20) { "End of block @ #{current_sample_position}" }

    debug(7) { ' * '.blue.bold + "Read block checksum     : #{Tools::octal(current_block.checksum).bold}" }
    debug(7) { ' * '.blue.bold + "Computed block checksum : #{Tools::octal(current_block.compute_checksum).bold}" }

    debug(5) { "Verifying block #{current_block.number.to_s.bold} checksum: #{current_block.validate_checksum ? 'success'.green : 'failed'.red }" }

    if current_block.validate_checksum then
      return current_block
    else
      return nil
    end
  end

end

# frozen_string_literal: true

module Disassembler
  # PDP-11 handbook: http://gordonbell.azurewebsites.net/digital/pdp%2011%20handbook%201969.pdf
  # Written with heavy inflience from https://github.com/caldwell/pdp11dasm

  REGISTER_NAMES = %w[ R0 R1 R2 R3 R4 R5 SP PC ]

  # Prefefined lavels contain a hash of names assigned to specific addresses.
  # For example: { 0o001000 => :START, 0o177714 => :IOPORT }
  def disassemble_with_labels(predefined_labels = {})
    @predefined_labels = predefined_labels
    disassemble(1)
    disassemble(2)
    disassemble(3)
  end

  def disassemble(pass = nil)
    str = nil

    case pass
    when 1 then # 1st pass to determine command base addresses
      @acceptable_label_addresses = []
    when 2 then # 2nd pass to determine labels
      @labels = {}      # Label corresponding to a particular address
      @references = {}  # Text indicating how to refer to a particular address
      @predefined_labels.each_pair { |address, label|
        @labels[address] = label.to_s
        @references[address] = label.to_s
      }
    when 3, nil
      str = +''
    end

    # TODO: currently start address must be even
    # TODO: add autostart detection
    # TODO: distinguish between local and global labels
    @current_offset = 0

    @previous_command = ''

    while @current_offset < body.length do
      start_offset = @current_offset
      @acceptable_label_addresses << (start_address + @current_offset) if pass == 1
      current_command, step, label, add_newline_after = decode_command

      next unless str # Do not bother building the output unless all labels are determined

      oct = Tools::octal(word_at(start_offset)) << ' '
      oct << ((step > 2) ? Tools::octal(word_at(start_offset + 2)) : '      ') << ' '
      oct << ((step > 4) ? Tools::octal(word_at(start_offset + 4)) : '      ')

      label += ':' unless label.nil? || (label == '')
      str << "#{Tools::octal(start_address + start_offset)}: #{oct}\t#{label}\t#{current_command}\n"
      str << "\n" if add_newline_after
    end

    str
  end

  def word_at(offset)
    Tools::bytes2word(body[offset], body[offset + 1])
  end

  # Output: a set of following values:
  #  * Complete command mnemonic;
  #  * Number of bytes current command with all parameters occupies;
  #  * Label that should precede the command.
  def decode_command
    command_start_offset = @current_offset
    current_word = Tools::bytes2word(body[@current_offset], body[@current_offset + 1])

    newline_after = cmd = nil

    case (current_word & 0o170000)
    when 0o000000 then
      case (current_word & 0o177000)
      when 0o000000 then
        case (current_word & 0o177700)
        when 0o000000 then
          case (current_word)
          when 0o000000 then cmd = 'HALT'
          when 0o000001 then cmd = 'WAIT'
          when 0o000002 then cmd = 'RTI'
          when 0o000003 then cmd = 'BPT'
          when 0o000004 then cmd = 'IOT'
          when 0o000005 then cmd = 'RESET'
          when 0o000006 then cmd = 'RTT'
          end
        when 0o000100 then
          cmd = ____DD('JMP', current_word)
          newline_after = true
        when 0o000200 then
          case (current_word)
          when (0o000200..0o000206) then
            cmd = [ "RTS", parse_operand(current_word & 0o7) ]
            newline_after = true
          when 0o000207 then
            cmd = 'RET'
            newline_after = true
          when 0o000240 then cmd = 'NOP'
          when 0o000241 then cmd = 'CLC'
          when 0o000242 then cmd = 'CLV'
          when 0o000244 then cmd = 'CLZ'
          when 0o000250 then cmd = 'CLN'
          when 0o000257 then cmd = 'CCC'
          when 0o000261 then cmd = 'SEC'
          when 0o000262 then cmd = 'SEV'
          when 0o000264 then cmd = 'SEZ'
          when 0o000270 then cmd = 'SEN'
          when 0o000277 then cmd = 'SCC'
          end
        when 0o000300 then
          cmd = ____DD('SWAB', current_word)
        when 0o000400, 0o000500, 0o000600, 0o000700 then
          cmd = ___XXX('BR', current_word)
          newline_after = true
        end
      when 0o001000 then
        case (current_word & 0o177400)
        when 0o001000 then
          cmd = ___XXX('BNE', current_word)
        when 0o001400 then
          cmd = ___XXX('BEQ', current_word)
        end
      when 0o002000 then
        case (current_word & 0o177400)
        when 0o002000 then
          cmd = ___XXX('BGE', current_word)
        when 0o002400 then
          cmd = ___XXX('BLT', current_word)
        end
      when 0o003000 then
        case (current_word & 0o177400)
        when 0o003000 then
          cmd = ___XXX('BGT', current_word)
        when 0o003400 then
          cmd = ___XXX('BLE', current_word)
        end
      when 0o004000 then # JSR - 004RDD
        r = (current_word >> 6) & 0o7

        if r == 7 then
          cmd = ____DD('CALL', current_word)
        else
          cmd = ___RDD('JSR', current_word)
        end
      when 0o005000 then
        case (current_word & 0o177700)
        when 0o005000 then
          cmd = ____DD('CLR', current_word)
        when 0o005100 then
          cmd = ____DD('COM', current_word)
        when 0o005200 then
          cmd = ____DD('INC', current_word)
        when 0o005300 then
          cmd = ____DD('DEC', current_word)
        when 0o005400 then
          cmd = ____DD('NEG', current_word)
        when 0o005500 then
          cmd = ____DD('ADC', current_word)
        when 0o005600 then
          cmd = ____DD('SBC', current_word)
        when 0o005700 then
          cmd = ____DD('TST', current_word)
        end
      when 0o006000 then
        case (current_word & 0o177700)
        when 0o006000 then
          cmd = ____DD('ROR', current_word)
        when 0o006100 then
          cmd = ____DD('ROL', current_word)
        when 0o006200 then
          cmd = ____DD('ASR', current_word)
        when 0o006300 then
          cmd = ____DD('ASL', current_word)
        when 0o006400 then
          cmd = [ "MARK", (current_word & 0o77).to_s(8) ]
        when 0o006500 then
          cmd = ____DD('MFPI', current_word)
        when 0o006600 then
          cmd = ____DD('MTPI', current_word)
        when 0o006700 then
          cmd = ____DD('SXT', current_word)
        end
      when 0o007000 then
        # Not used
      end
    when 0o010000 then
      cmd = __SSDD('MOV', current_word)
    when 0o020000 then
      cmd = __SSDD('CMP', current_word)
    when 0o030000 then
      cmd = __SSDD('BIT', current_word)
    when 0o040000 then
      cmd = __SSDD('BIC', current_word)
    when 0o050000 then
      cmd = __SSDD('BIS', current_word)
    when 0o060000 then
      cmd = __SSDD('ADD', current_word)
    when 0o070000 then
      case (current_word & 0o177000)
      when 0o074000 then
        cmd = ___RDD('XOR', current_word)
      when 0o077000 then
        address = (start_address + @current_offset + 2 - ((current_word & 0o77) * 2))
        cmd = [ "SOB", parse_operand((current_word >> 6) & 0o7), address_or_label(address) ]
        newline_after = true
      end
    when 0o100000 then
      case (current_word & 0o177000)
      when 0o100000 then
        case (current_word & 0o177400)
        when 0o100000 then
          cmd = ___XXX('BPL', current_word)
        when 0o100400 then
          cmd = ___XXX('BMI', current_word)
        end
      when 0o101000 then
        case (current_word & 0o177400)
        when 0o101000 then
          cmd = ___XXX('BHI', current_word)
        when 0o101400 then #
          cmd = ___XXX('BLOS', current_word)
        end
      when 0o102000 then
        case (current_word & 0o177400)
        when 0o102000 then
          cmd = ___XXX('BVC', current_word)
        when 0o102400 then
          cmd = ___XXX('BVS', current_word)
        end
      when 0o103000 then
        case (current_word & 0o177400)
        when 0o103000 then
          if @previous_command =~ /^CMP/i then # Immediately after comparison, BHIS makes better sense than BCC
            cmd = ___XXX('BHIS', current_word)
          else
            cmd = ___XXX('BCC', current_word)
          end
        when 0o103400 then
          if @previous_command =~ /^CMP/i then # Immediately after comparison, BLO makes better sense than BCS
            cmd = ___XXX('BLO', current_word)
          else
            cmd = ___XXX('BCS', current_word)
          end
        end
      when 0o104000 then
        oper = (current_word & 0o377).to_s(8)
        case (current_word & 0o104400)
        when 0o104000 then
          cmd = [ "EMT", oper ]
        when 0o104400 then
          cmd = [ "TRAP", oper ]
        end
      when 0o105000 then
        case (current_word & 0o177700)
        when 0o105000 then
          cmd = ____DD('CLRB', current_word)
        when 0o105100 then
          cmd = ____DD('COMB', current_word)
        when 0o105200 then
          cmd = ____DD('INCB', current_word)
        when 0o105300 then
          cmd = ____DD('DECB', current_word)
        when 0o105400 then
          cmd = ____DD('NEGB', current_word)
        when 0o105500 then
          cmd = ____DD('ADCB', current_word)
        when 0o105600 then
          cmd = ____DD('SBCB', current_word)
        when 0o105700 then
          cmd = ____DD('TSTB', current_word)
        end
      when 0o106000 then
        case (current_word & 0o177700)
        when 0o106000 then
          cmd = ____DD('RORB', current_word)
        when 0o106100 then
          cmd = ____DD('ROLB', current_word)
        when 0o106200 then
          cmd = ____DD('ASRB', current_word)
        when 0o106300 then
          cmd = ____DD('ASLB', current_word)
        when 0o106400 then
          cmd = ____DD('MTPS', current_word)
        when 0o106700 then
          cmd = ____DD('MFPS', current_word)
        end
      end
    when 0o110000 then
      cmd = __SSDD('MOVB', current_word)
    when 0o120000 then
      cmd = __SSDD('CMPB', current_word)
    when 0o130000 then
      cmd = __SSDD('BITB', current_word)
    when 0o140000 then
      cmd = __SSDD('BICB', current_word)
    when 0o150000 then
      cmd = __SSDD('BISB', current_word)
    when 0o160000 then
      cmd = __SSDD('SUB', current_word)
    end

    case cmd
    when nil then
      # If by now we haven't found a valid command, it must be a constant.
      cmd = '.#' + current_word.to_s(8)
    when Array then
      cmd = "#{cmd.shift}\t#{cmd.join(",")}"
    end

    label = defined?(@labels) && @labels[start_address + command_start_offset]
    @current_offset += 2
    @previous_command = cmd
    [ cmd, @current_offset - command_start_offset, label, newline_after ]
  end

  def __SSDD(cmd, word)
    cmd + "\t" + parse_operand((word >> 6) & 0o77) + ',' + parse_operand(word & 0o77)
  end

  def ____DD(cmd, word)
    cmd + "\t" + parse_operand(word & 0o77)
  end

  def ___RDD(cmd, word)
    cmd + "\t" + parse_operand((word >> 6) & 0o7) + ',' + parse_operand(word & 0o77)
  end

  def ___XXX(cmd, word)
    cmd + "\t" + address_or_label(offset2address(word & 0o377))
  end

  def parse_operand(code)
    r = code & 0o7

    case (code & 0o70)
    when 0o00 then REGISTER_NAMES[r]
    when 0o10 then "(#{REGISTER_NAMES[r]})"
    when 0o20 then
      if r == 7 then
        @current_offset += 2
        "##{word_at(@current_offset).to_s(8)}"
      else "(#{REGISTER_NAMES[r]})+"
      end
    when 0o30 then
      if r == 7 then
        @current_offset += 2
        address = word_at(@current_offset)
        "@##{address_or_label(address)}"
      else "@(#{REGISTER_NAMES[r]})+"
      end
    when 0o40 then "-(#{REGISTER_NAMES[r]})"
    when 0o50 then "@-(#{REGISTER_NAMES[r]})"
    when 0o60 then
      @current_offset += 2

      offset = word_at(@current_offset)

      if r == 7 then
        address_or_label((start_address + @current_offset + offset + 2) & 0o177777)
      else
        "#{offset.to_s(8)}(#{REGISTER_NAMES[r]})"
      end
    when 0o70 then
      @current_offset += 2

      offset = word_at(@current_offset)

      if r == 7 then
        "@#{address_or_label((start_address + @current_offset + offset + 2) & 0o177777)}"
      else
        "@#{offset.to_s(8)}(#{REGISTER_NAMES[r]})"
      end

    end
  end

  def offset2address(offset)
    offset = (offset - 0o400) if offset > 0o200
    start_address + (@current_offset + 2) + (offset * 2)
  end

  def make_new_label
    @label_no ||= 0
    "L#{@label_no += 1}"
  end

  def get_label(address)
    return nil unless defined?(@labels)

    if defined?(@references) then
      cached_reference = @references[address]
      return cached_reference if cached_reference
    end

    if @acceptable_label_addresses.include?(address) then
      @labels[address] ||= make_new_label
      @references[address] = @labels[address]
    else
      closest_address = @acceptable_label_addresses.select{ |a| a <= address }.max
      @labels[closest_address] ||= make_new_label
      @references[address] = "#{@labels[closest_address]}+#{address - closest_address}"
    end
  end

  def address_or_label(address)
    if (address >= start_address) && (address <= (start_address + length)) then
      label = get_label(address)
      return label if label
    end

    address.to_s(8)
  end

end

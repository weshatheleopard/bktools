# frozen_string_literal: true

module Disassembler
  # PDP-11 handbook: http://gordonbell.azurewebsites.net/digital/pdp%2011%20handbook%201969.pdf
  # Written with heavy inflience from https://github.com/caldwell/pdp11dasm

  REGISTER_NAMES = %w[ R0 R1 R2 R3 R4 R5 SP PC ]

  def disassemble_with_labels(predefined_labels = {})
    # TODO: populate @labels and @references from predefined_labels
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
      current_command, step, label = decode_command

      next unless str

      oct = Tools::octal(word_at(start_offset)) << ' '
      oct << ((step > 2) ? Tools::octal(word_at(start_offset + 2)) : '      ') << ' '
      oct << ((step > 4) ? Tools::octal(word_at(start_offset + 4)) : '      ')

      label += ':' unless label.nil? || (label == '')
      str << "#{Tools::octal(start_address + start_offset)}: #{oct}\t#{label}\t#{current_command}\n"
      str << "\n" if current_command =~ /^(JMP|RTS|RET|BR|SOB)/
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

    cmd = ''
    case (current_word & 0o170000)
    when 0o000000 then
      case (current_word & 0o177000)
      when 0o000000 then
        case (current_word & 0o177700)
        when 0o000000 then
          case (current_word)
          when 0 then cmd = 'HALT'
          when 1 then cmd = 'WAIT'
          when 2 then cmd = 'RTI'
          when 3 then cmd = 'BPT'
          when 4 then cmd = 'IOT'
          when 5 then cmd = 'RESET'
          when 6 then cmd = 'RTT'
          end
        when 0o000100 then
          cmd = dd('JMP', current_word)
        when 0o000200 then
          case (current_word)
          when 0o200, 0o201, 0o202, 0o203, 0o204, 0o205, 0o206 then
            cmd = "RTS\t" + parse_operand(current_word & 0o7)
          when 0o207 then
            cmd = 'RET'
          when 0o240 then cmd = 'NOP'
          when 0o241 then cmd = 'CLC'
          when 0o242 then cmd = 'CLV'
          when 0o244 then cmd = 'CLZ'
          when 0o250 then cmd = 'CLN'
          when 0o257 then cmd = 'CCC'
          when 0o261 then cmd = 'SEC'
          when 0o262 then cmd = 'SEV'
          when 0o264 then cmd = 'SEZ'
          when 0o270 then cmd = 'SEN'
          when 0o277 then cmd = 'SCC'
          end
        when 0o000300 then
          cmd = dd('SWAB', current_word)
        when 0o000400, 0o000500, 0o000600, 0o000700 then
          cmd = off('BR', current_word)
        end
      when 0o001000 then
        case (current_word & 0o177400)
        when 0o001000 then
          cmd = off('BNE', current_word)
        when 0o001400 then
          cmd = off('BEQ', current_word)
        end
      when 0o002000 then
        case (current_word & 0o177400)
        when 0o002000 then
          cmd = off('BGE', current_word)
        when 0o002400 then
          cmd = off('BLT', current_word)
        end
      when 0o003000 then
        case (current_word & 0o177400)
        when 0o003000 then
          cmd = off('BGT', current_word)
        when 0o003400 then
          cmd = off('BLE', current_word)
        end
      when 0o004000 then # JSR - 004RDD
        r = (current_word >> 6) & 0o7

        if r == 7 then
          cmd = dd('CALL', current_word)
        else
          cmd = rdd('JSR', current_word)
        end
      when 0o005000 then
        case (current_word & 0o177700)
        when 0o005000 then
          cmd = dd('CLR', current_word)
        when 0o005100 then
          cmd = dd('COM', current_word)
        when 0o005200 then
          cmd = dd('INC', current_word)
        when 0o005300 then
          cmd = dd('DEC', current_word)
        when 0o005400 then
          cmd = dd('NEG', current_word)
        when 0o005500 then
          cmd = dd('ADC', current_word)
        when 0o005600 then
          cmd = dd('SBC', current_word)
        when 0o005700 then
          cmd = dd('TST', current_word)
        end
      when 0o006000 then
        case (current_word & 0o177700)
        when 0o006000 then
          cmd = dd('ROR', current_word)
        when 0o006100 then
          cmd = dd('ROL', current_word)
        when 0o006200 then
          cmd = dd('ASR', current_word)
        when 0o006300 then
          cmd = dd('ASL', current_word)
        when 0o006400 then
          cmd = "MARK\t" + (current_word & 0o77).to_s(8)
        when 0o006500 then
          cmd = dd('MFPI', current_word)
        when 0o006600 then
          cmd = dd('MTPI', current_word)
        when 0o006700 then
          cmd = dd('SXT', current_word)
        end
      when 0o007000 then
        # Not used
      end
    when 0o010000 then
      cmd = ssdd('MOV', current_word)
    when 0o020000 then
      cmd = ssdd('CMP', current_word)
    when 0o030000 then
      cmd = ssdd('BIT', current_word)
    when 0o040000 then
      cmd = ssdd('BIC', current_word)
    when 0o050000 then
      cmd = ssdd('BIS', current_word)
    when 0o060000 then
      cmd = ssdd('ADD', current_word)
    when 0o070000 then
      case (current_word & 0o177000)
      when 0o074000 then
        cmd = rdd('XOR', current_word)
      when 0o077000 then
        address = (start_address + @current_offset + 2 - ((current_word & 0o77) * 2))
        cmd = "SOB\t" + parse_operand((current_word >> 6) & 0o7) + ',' + address_or_label(address)
      end
    when 0o100000 then
      case (current_word & 0o177000)
      when 0o100000 then
        case (current_word & 0o177400)
        when 0o100000 then
          cmd = off('BPL', current_word)
        when 0o100400 then
          cmd = off('BMI', current_word)
        end
      when 0o101000 then
        case (current_word & 0o177400)
        when 0o101000 then
          cmd = off('BHI', current_word)
        when 0o101400 then #
          cmd = off('BLOS', current_word)
        end
      when 0o102000 then
        case (current_word & 0o177400)
        when 0o102000 then
          cmd = off('BVC', current_word)
        when 0o102400 then
          cmd = off('BVS', current_word)
        end
      when 0o103000 then
        case (current_word & 0o177400)
        when 0o103000 then
          if @previous_command =~ /^CMP/i then # Immediately after comparison, BHIS makes better sense than BCC
            cmd = off('BHIS', current_word)
          else
            cmd = off('BCC', current_word)
          end
        when 0o103400 then
          if @previous_command =~ /^CMP/i then # Immediately after comparison, BLO makes better sense than BCS
            cmd = off('BLO', current_word)
          else
            cmd = off('BCS', current_word)
          end
        end
      when 0o104000 then
        oper = (current_word & 0o377).to_s(8)
        case (current_word & 0o104400)
        when 0o104000 then
          cmd = "EMT\t" + oper
        when 0o104400 then
          cmd = "TRAP\t" + oper
        end
      when 0o105000 then
        case (current_word & 0o177700)
        when 0o105000 then
          cmd = dd('CLRB', current_word)
        when 0o105100 then
          cmd = dd('COMB', current_word)
        when 0o105200 then
          cmd = dd('INCB', current_word)
        when 0o105300 then
          cmd = dd('DECB', current_word)
        when 0o105400 then
          cmd = dd('NEGB', current_word)
        when 0o105500 then
          cmd = dd('ADCB', current_word)
        when 0o105600 then
          cmd = dd('SBCB', current_word)
        when 0o105700 then
          cmd = dd('TSTB', current_word)
        end
      when 0o106000 then
        case (current_word & 0o177700)
        when 0o106000 then
          cmd = dd('RORB', current_word)
        when 0o106100 then
          cmd = dd('ROLB', current_word)
        when 0o106200 then
          cmd = dd('ASRB', current_word)
        when 0o106300 then
          cmd = dd('ASLB', current_word)
        when 0o106400 then
          cmd = dd('MTPS', current_word)
        when 0o106700 then
          cmd = dd('MFPS', current_word)
        end
      end
    when 0o110000 then
      cmd = ssdd('MOVB', current_word)
    when 0o120000 then
      cmd = ssdd('CMPB', current_word)
      @comparison_status = :comparison_command
    when 0o130000 then
      cmd = ssdd('BITB', current_word)
    when 0o140000 then
      cmd = ssdd('BICB', current_word)
    when 0o150000 then
      cmd = ssdd('BISB', current_word)
    when 0o160000 then
      @cmp_step = 1
      cmd = ssdd('SUB', current_word)
    end

    # If by now we haven't found a valid command, it must be a constant.
    cmd = '.#' + current_word.to_s(8) if cmd == ''

    label = defined?(@labels) && @labels[start_address + command_start_offset]
    @current_offset += 2
    @previous_command = cmd
    [ cmd, @current_offset - command_start_offset, label ]
  end

  def ssdd(cmd, word)
    cmd + "\t" + parse_operand((word >> 6) & 0o77) + ',' + parse_operand(word & 0o77)
  end

  def dd(cmd, word)
    cmd + "\t" + parse_operand(word & 0o77)
  end

  def rdd(cmd, word)
    cmd + "\t" + parse_operand((word >> 6) & 0o7) + ',' + parse_operand(word & 0o77)
  end

  def off(cmd, word)
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

module Focal

  EOF_OFFSET = 0176026

  def focal2txt
    # Return nothing if the file is not a Focal program
    return nil if start_address != 01752
    offset = 0

    result = ''

    until offset == EOF_OFFSET do
      line, offset = parse_line(offset)
      result << line << "\n"
    end

    result
  end

  def parse_line(offset)
    line_content = ''
    next_line_offset = (Tools::bytes2word(body[offset], body[offset + 1]) + offset + 2)
    next_line_offset += 1 if next_line_offset.odd?
    next_line_offset = next_line_offset & 0o177777

    offset +=2

    line_group = body[offset + 1]
    line_no = body[offset] # There's some strange conversion routine here, I'll investigate later

    offset +=2

    loop do
      c = body[offset]

      break if c == 0216

      line_content +=
        case c
        when 0200 then ' '
        when 0201 then '+'
        when 0202 then '-'
        when 0203 then '/'
        when 0204 then '*'
        when 0205 then '^'
        when 0206 then '('
        when 0207 then '['
        when 0210 then '>'
        when 0211 then ')'
        when 0212 then ']'
        when 0213 then '<'
        when 0214 then ','
        when 0215 then ';'
        when 0216 then "\n"
        when 0217 then '='
        else c.chr
        end

      offset += 1
    end

    return [ "#{line_group}.#{line_no} #{line_content}", next_line_offset ]
  end

end

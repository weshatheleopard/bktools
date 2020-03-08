module Focal

  EOF_OFFSET = 0176026

  def focal2txt
    # Return nothing if the file is not a Focal program
    return nil if start_address != 01752
    offset = 0

    result = ''

    until offset == EOF_OFFSET do
      line, offset = parse_line(offset)
      result << line << "\n" if line
    end

    result
  end

  def parse_line(offset)
    line_content = ''
    next_line_offset = (Tools::bytes2word(body[offset], body[offset + 1]) + offset + 2)
    next_line_offset += 1 if next_line_offset.odd?
    next_line_offset = next_line_offset & 0o177777

    offset +=2

    line_val = Tools::bytes2word(body[offset], body[offset + 1]) * 1000 / 256

    if line_val == 0 then
      return [ nil, next_line_offset ]
    end

    # I still do not understand this logic here, but it seems to be functioning properly.
    # Thanks Alexander Lunev for the idea -- http://bk0010.narod.ru/readme.html
    line_group = line_val / 1000
    line_no = line_val % 1000
    line_no += 10 if (line_no % 10) >= 5
    line_no = line_no / 10

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
        when 0210 then '<'
        when 0211 then ')'
        when 0212 then ']'
        when 0213 then '>'
        when 0214 then ','
        when 0215 then ';'
        when 0216 then "\n"
        when 0217 then '='
        else c.chr
        end

      offset += 1
    end
 
    line_no = "0#{line_no}" if line_no < 10
    return [ "#{line_group}.#{line_no} #{line_content}", next_line_offset ]
  end

end

class BkFile

  attr_accessor :start_address
  attr_accessor :length
  attr_accessor :body
  attr_accessor :name
  attr_accessor :checksum

  def initialize
    @body = []
  end

  def print_line(base_addr, data_str, char_str)
    data_str = (data_str + ' ' * 28)[0...28]
    print Tools::octal(base_addr), ': ', data_str, ' ', char_str, "\n"
    data_str = ''
    char_str = ''
  end

  def display(options = {})
    puts "File name:     [#{(name + ' ' * 16)[0...16]}]"
    puts "Start address: #{Tools::octal(self.start_address)}"
    puts "Data length:   #{Tools::octal(self.length)}"

    b0 = b1 = nil
    out_str = ''
    data_str = ''
    char_str = ''
    addr = start_address
    newline = true
    i = 0

    if addr.odd? then
      addr -=1
      data_str = data_str + "   #{Tools::octal_byte(body[0])} "
      char_str += ' '
      i = 1
    end

    data_str_start = addr

    while (i < length) do

      byte = body[i]

      c = (byte < 32) ? '.' : byte.chr
      char_str << c

      if b0.nil? then
        b0 = byte
      else
        b1 = byte
      end

      if b0 && b1 then
        data_str << Tools::octal(Tools::bytes2word(b0, b1)) << ' '
        b0 = b1 = nil
      end

      i +=1

      if (i % 8) == 0 then
        print_line(data_str_start, data_str, char_str)
        data_str = ''
        char_str = ''
        data_str_start = i
      end

    end

    if b0 then
      data_str << Tools::octal_byte(b0)
    end

    if !data_str.empty? then
      print_line(data_str_start, data_str, char_str)
    end

  end

  def compute_checksum
    cksum = 0
    body.each { |byte|
      cksum += byte
      if cksum > 0o177777 then
        cksum = cksum - 0o200000 + 1 # 16-bit cutoff + ADC
      end
    }
    cksum
  end

  def validate_checksum
    checksum == compute_checksum
  end

end

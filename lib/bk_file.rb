require 'term/ansicolor'
include Term::ANSIColor

require 'disassembler'
include Disassembler

require 'bk_image'
include BkImage

require 'tools'

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
    data_str = ''
    char_str = ''
    i = 0

    string_counter = 0
    string_start_addr = start_address

    if start_address.odd? then
      string_start_addr = start_address - 1
      string_counter = 2
      data_str = data_str + "   #{Tools::octal_byte(body[0])} "
      char_str += ' ' + Tools::byte2char(body[0])
      i = 1
    end

    while (i < length) do
      byte = body[i]

      char_str << Tools::byte2char(byte)

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
      string_counter += 1

      if (string_counter % 8) == 0 then
        print_line(string_start_addr, data_str, char_str)
        data_str = ''
        char_str = ''
        string_start_addr += 8
        string_counter = 0
      end

    end

    if b0 then
      data_str << Tools::octal_byte(b0)
    end

    if !data_str.empty? then
      print_line(string_start_addr, data_str, char_str)
    end

  end

  def compute_checksum
    Tools::checksum(body)
  end

  def validate_checksum
    checksum == compute_checksum
  end

  # Compare 2 files (obtained from different recordings) to find discrepancies
  def compare(other)
    flag = true

    self.body.each_with_index { |v, i|
      if v != other.body[i] then
        puts "Index: #{Tools::octal(i)}  This: #{Tools::octal(v)}  Other: #{Tools::octal(other.body[i])}"
        flag = false
      end
    }

    flag
  end

  def safe_name
    name.gsub(/[^0-9a-zA-Z\!\@\#\$\%\^\&\(\)\[\]\{\}\-\=\_\+\.\,\'\ ]/, '_')
  end

  def save(prefix = "bkfile")
    base_name = "#{prefix}.[#{safe_name}]"

    if start_address.nil? then
      puts "Start address not defined (file not loaded?)".red
      return
    end

    if name.nil? || name.empty? || name.length != 16 then
      puts "File name not defined (file not loaded?)".red
      return
    end

    if body.empty? then
      puts "File body is empty (file not loaded?)".red
      return
    end

    File.open("#{base_name}.bin", 'wb') { |f|
      body.each { |byte| f << byte.chr }
    }

    File.open("#{base_name}.metadata", 'wb') { |f|
      f.puts  "File name     : [#{name}]"
      f.puts  "Start address : #{Tools::octal(start_address)}"
      f.puts  "File length   : #{Tools::octal(length)}"
      f.puts  "Tape checksum : #{Tools::octal(checksum)}"
      f.puts  "Data checksum : #{Tools::octal(compute_checksum)}"
    }

    return true
  end

  def self.load(name, force = false)
    bkf = self.new

    File.open("#{name}.bin", 'rb') { |f|
      bkf.body = []
      data = f.read
      data.each_byte { |b| bkf.body << b }
    }

    File.open("#{name}.metadata", 'rb') { |f|
      f.each_line { |str|
        # We don't want Ruby to mess around with strings and encodings, so
        # we're going to manipulate pure bytes.

        title = str.bytes[0..15].pack('c*')
        value = str.bytes[16..-2]

        case title
        when "File name     : " then
          bkf.name = value[1..-2].pack('c*')
        when "Start address : " then
          bkf.start_address = Tools::read_octal(value.pack('c*'))
        when "File length   : "
          bkf.length = Tools::read_octal(value.pack('c*'))
        when "Tape checksum : " then
          bkf.checksum = Tools::read_octal(value.pack('c*'))
        when "Data checksum : " then
          data_checksum = bkf.compute_checksum
          raise if force || (data_checksum != Tools::read_octal(value.pack('c*')))
        end
      }
    }

    return bkf
  end

  def binary_content
    body.pack('c*')
  end

  def inspect
    b = if @body.size > 16 then
          @body[0..16].inspect.gsub(']', ', ...]')
        else
          @body.inspect
        end

    "#<#{self.class} start_address=" +
      (@start_address.nil? ? 'nil' : Tools::octal(@start_address)) +
      ' name: ' + @name.inspect +
      ' length: '   + (@length.nil? ? 'nil' : Tools::octal(@length)) +
      ' checksum: ' + (@checksum.nil? ? 'nil' : Tools::octal(@checksum)) +
      ' body: ' + b.to_s +
      '>'
  end

end

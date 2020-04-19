require 'term/ansicolor'
include Term::ANSIColor

# Read data from track flux file produced by KryoFlux -- https://www.kryoflux.com/

class FddReader

  def initialize(filename, debuglevel = 0)
    @debuglevel = debuglevel
    @filename = filename
    @stream = nil
    @pos = 0
  end

  def read_track
    File.open(@filename, "rb") { |f| @stream = f.read.bytes }

    loop do
    
      block_type = @stream[@pos]
      @pos += 1

      case block_type
      when 0x00..0x07 then
        lsb = @stream[@pos]
        @pos += 1

        flux_val = (block_type << 8) + lsb;
        debug(20) { puts "Flux2 block: #{flux_val}" }
      when 0x08 then nil # NOP1 block, skip 1 byte total
      when 0x09 then @pos += 1 # NOP2 block, skip 2 bytes total
      when 0x0A then @pos += 2 # NOP3 block, skip 3 bytes total
      when 0x0B then
        raise "OVL16 currently not supported"
      when 0x0D then 
        break if out_of_stream_block
      when 0x0E..0xFF then
        debug(20) { "Flux1 block: #{block_type}" }
      else
        raise "Unknown block type: %02x" % [block_type]
      end
    end

  end

  def out_of_stream_block
    puts "* Out-of-stream Block:"
    oob_block_type = @stream[@pos]
    @pos +=1
    sz = read_word

    case oob_block_type
    when 0x00 then
      raise "Invalid OOB"
    when 0x01 then puts "Stream Information (multiple per track)---"
      raise "Protocol error" if sz != 8
   
      stream_position = read_dword
      transfer_time = read_dword
puts stream_position, transfer_time


    when 0x02 then puts "Index signal data"
      raise "Protocol error" if sz != 12
   
      stream_position = read_dword
      sample_counter = read_dword
      index_counter = read_dword

puts stream_position, sample_counter, index_counter


    when 0x03 then 
      puts "StreamEnd - No more flux to transfer (one per track)"
      raise "Protocol error" if sz != 8

      stream_position = read_dword
      result_code = read_dword

puts stream_position, result_code

    when 0x04 then
      str = ""
      sz.times {
        str << @stream[@pos].chr
        @pos += 1
      }

      puts "   KryoFlux device info: [#{str}] size=#{sz}"
    when 0x0D then
      puts "EOF --  (no more data to process)"
      return true
    else raise
    end
    return false
  end

  def read_word
    word = Tools::bytes2word(@stream[@pos], @stream[@pos+1])
    @pos += 2
    word
  end

  def read_dword
    dword = @stream[@pos] |
             (@stream[@pos+1] << 8) |
             (@stream[@pos+2] << 16) |
             (@stream[@pos+3] << 24)
    @pos += 4
    dword
  end
  
  def debug(msg_level)
    return if msg_level > @debuglevel
    msg = yield
    puts(msg) if msg
  end

end

=begin
f = FddReader.new('trk00.0.raw')
f.read
=end

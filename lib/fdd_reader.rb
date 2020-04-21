require 'wavefile'
include WaveFile

require 'term/ansicolor'
include Term::ANSIColor

# Read data from track flux file produced by KryoFlux -- https://www.kryoflux.com/

class FddReader
  attr_accessor :track_array

  def initialize(filename, debuglevel = 0)
    @debuglevel = debuglevel
    @filename = filename
    @stream = nil
    @file_position = 0
    @stream_position = 0
    @track_array = []
  end

  def read_track
    File.open(@filename, "rb") { |f| @stream = f.read.bytes }

    @revolution_array = []

    loop do
      block_type = @stream[@file_position]
      @file_position += 1

      case block_type
      when 0x00..0x07 then
        lsb = @stream[@file_position]
        flux_val = (block_type << 8) + lsb
        add_flux(flux_val, @stream_position)
        @file_position += 1
        @stream_position += 2
      when 0x08 then # NOP1 block, skip 1 byte
        @stream_position += 1
      when 0x09 then # NOP2 block, skip 2 bytes
        @stream_position += 2
        @file_position += 1
      when 0x0A then # NOP3 block, skip 3 bytes
        @stream_position += 3
        @file_position += 2
      when 0x0B then
        raise "OVL16 block currently not supported"
      when 0x0D then
        break if out_of_stream_block
      when 0x0E..0xFF then
        add_flux(block_type, @stream_position)
        @stream_position += 1
      else
        raise "Unknown block type: %02x" % [block_type]
      end
    end

  end

  def add_flux(val, stream_position)
    debug(20) { "#{stream_position} => #{block_val}" }
    @revolution_array << val
  end

  def out_of_stream_block
    oob_block_type = @stream[@file_position]
    @file_position +=1
    sz = read_word

    case oob_block_type
    when 0x00 then
      raise "Invalid OOB"
    when 0x01 then
      raise "Protocol error" if sz != 8

      stream_position = read_dword
      transfer_time = read_dword

      debug(10) {
        "Stream Information".yellow +
          "\n  * KryoFlux stream position : " + stream_position.to_s.bold +
          "\n  * Reader stream position   : " + @stream_position.to_s.bold +
          "\n  * Transfer time (ms)       : " + transfer_time.to_s.bold
      }
    when 0x02 then
      raise "Protocol error" if sz != 12

      stream_position = read_dword
      sample_counter = read_dword
      index_counter = read_dword

      debug(10) {
        "Index signal data".blue.bold +
          "\n  * Next KryoFlux stream position  : " + stream_position.to_s.bold +
          "\n  * Sample Counter since last flux : " + sample_counter.to_s.bold +
          "\n  * Index Clock value              : " + index_counter.to_s.bold
      }

      @track_array << @revolution_array if @revolution_array
      @revolution_array = []
    when 0x03 then
      raise "Protocol error" if sz != 8
      stream_position = read_dword
      result_code = read_dword

      debug(5) {
        "Stream End".red +
          "\n  * KryoFlux stream position : " + stream_position.to_s.bold +
          "\n  * Return code              : " + result_code.to_s.bold
      }
    when 0x04 then
      str = ""
      sz.times {
        str << @stream[@file_position].chr
        @file_position += 1
      }

      puts "KryoFlux device info".magenta + "\n  * [#{str}] (#{sz})"
    when 0x0D then
      debug(5) { "End of file".red }
      return true
    else raise
    end
    return false
  end

  def read_word
    word = Tools::bytes2word(@stream[@file_position], @stream[@file_position+1])
    @file_position += 2
    word
  end

  def read_dword
    dword = @stream[@file_position] |
             (@stream[@file_position+1] << 8) |
             (@stream[@file_position+2] << 16) |
             (@stream[@file_position+3] << 24)
    @file_position += 4
    dword
  end

  def debug(msg_level)
    return if msg_level > @debuglevel
    msg = yield
    puts(msg) if msg
  end

  # Method for saving track as wav for reviewing it in a sound editor
  def save_track_as_wav(arr, filename)
    @buffer = Buffer.new([ ], Format.new(:mono, :pcm_16, 22050))
    val = 30000
    arr.each_with_index { |v, i|
      (v/5).to_i.times { @buffer.samples << ((i.even?) ? 30000 : -30000 ) }
    }

    Writer.new(filename, Format.new(:mono, :pcm_8, 22050)) { |writer| writer.write(@buffer) }
  end


end

# f = FddReader.new('trk00.0.raw'); f.read_track

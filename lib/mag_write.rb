require 'wavefile'
require 'term/ansicolor'
include Term::ANSIColor

class MagWrite
  include WaveFile

  attr_accessor :bk_file

  ZERO_LEVEL = 15000
  ONE_LEVEL = 30000
  DEFAULT_POS_CYCLES = 23
  DEFAULT_NEG_CYCLES = 22

  ZERO_POS_CYCLES = 24
  ZERO_NEG_CYCLES = 23

  ONE_POS_CYCLES = 51
  ONE_NEG_CYCLES = 51

  SOBS_TO_PULSES_COEFF = 3.3

  def initialize(bk_file)
    @bit_length = 10
    @bk_file = bk_file
  end

  def save(filename)
    @buffer = Buffer.new([ ], Format.new(:mono, :pcm_16, 44100))

    header_array = Tools::word_to_byte_array(@bk_file.start_address) +
                     Tools::word_to_byte_array(@bk_file.length) +
                     Tools::string_to_byte_array(@bk_file.name)

    write_marker(0o10000)
    write_marker(8)
    write_byte_sequence(header_array)
    write_marker(8)
    write_byte_sequence(@bk_file.body)
    write_byte_sequence(Tools::word_to_byte_array(@bk_file.compute_checksum))
    write_marker(256, 256)

    Writer.new(filename, Format.new(:mono, :pcm_16, 44100)) { |writer| writer.write(@buffer) }
  end

  def write_marker(impulse_count, first_impulse_length = 0)
    write_impulse(ZERO_LEVEL, first_impulse_length + DEFAULT_POS_CYCLES, first_impulse_length + DEFAULT_NEG_CYCLES)
    (impulse_count - 1).times { write_bit(0) }
    write_impulse(ONE_LEVEL, 105, 100)
    write_data_bit(1)
  end
  
  def write_byte_sequence(array)
    array.each { |byte| write_byte(byte) }
  end

  def write_byte(byte)
    8.times do
      write_data_bit(byte & 1)
      byte = byte >> 1
    end
  end

  def write_data_bit(bit)
    write_bit(bit)
    write_bit(0)
  end

  def write_bit(bit)
    case bit
    when 0, true  then
      write_impulse(ZERO_LEVEL, ZERO_POS_CYCLES, ZERO_NEG_CYCLES)
    when 1, false then
      write_impulse(ONE_LEVEL, ONE_POS_CYCLES, ONE_NEG_CYCLES)
    else raise "Incorrect parameter"
    end
  end

  def write_impulse(volume, length_pos = 0, length_neg = 0)
    (length_pos.to_f / SOBS_TO_PULSES_COEFF).to_i.times { @buffer.samples << volume }
    (length_neg.to_f / SOBS_TO_PULSES_COEFF).to_i.times { @buffer.samples << -volume }
  end

end

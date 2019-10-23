require 'wavefile'
require 'term/ansicolor'
include Term::ANSIColor

class MagWrite
  include WaveFile

  attr_accessor :bk_file

  ZERO_LEVEL = 15000
  ONE_LEVEL = 30000
  SOBS_TO_PULSES_COEFF = 3.3

  def initialize(bk_file)
    @bit_length = 10
    @buffer = Buffer.new([ ], Format.new(:mono, :pcm_16, 44100))
    @bk_file = bk_file
  end

  def save(filename)
    header_array = Tools::word_to_byte_array(@bk_file.start_address) +
                     Tools::word_to_byte_array(@bk_file.length) +
                     Tools::string_to_byte_array(@bk_file.name)

    write_marker(0o10000, 0)
    write_marker(8, 0)
    write_byte_sequence(header_array)
    write_marker(8, 0)
    write_byte_sequence(@bk_file.body)
    write_byte_sequence(Tools::word_to_byte_array(@bk_file.compute_checksum))
    write_marker(256, 256)

    Writer.new(filename, Format.new(:mono, :pcm_16, 44100)) { |writer| writer.write(@buffer) }
  end

  def write_marker(impulse_count, first_impulse_length)
    write_pulse(23 + first_impulse_length, ZERO_LEVEL)
    write_pulse(22 + first_impulse_length, -ZERO_LEVEL)
    (impulse_count - 1).times { write_bit(0) }
    write_pulse(105, ONE_LEVEL)
    write_pulse(100, -ONE_LEVEL)
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
      write_pulse(23, ZERO_LEVEL)
      write_pulse(22, -ZERO_LEVEL)
    when 1, false then
      write_pulse(51, ONE_LEVEL)
      write_pulse(51, -ONE_LEVEL)
    else raise
    end
  end

  def write_pulse(length, size)
    (length.to_f / SOBS_TO_PULSES_COEFF).to_i.times { @buffer.samples << size }
  end

end

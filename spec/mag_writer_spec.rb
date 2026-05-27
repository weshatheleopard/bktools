require 'mag_writer'
require 'pp'

RSpec.describe MagWriter do
  let(:bk_file) do
    f = BkFile.new
    f.start_address = 0o1000
    f.length = 0o2000
    f.body = Array.new(f.length, 0b10101010)
    f.name = 'TESTtest123'
    f
  end

  context "in sinde mode" do
    let(:writer) { MagWriter.new(bk_file) }

    it "should populate the butter successfully" do
      expect { writer.write_to_buffer }.not_to raise_error

      samples = PP.pp(writer.buffer.samples, '')
      expect(samples).to be_same_value_as(:log => 'spec/result_data/mag_write_buffer_sine.ref')
    end
  end

  context "in sinde mode" do
    let(:writer) { MagWriter.new(bk_file, mode: :square) }

    it "should populate the butter successfully" do        
      expect { writer.write_to_buffer }.not_to raise_error

      samples = PP.pp(writer.buffer.samples, '')
      expect(samples).to be_same_value_as(:log => 'spec/result_data/mag_write_buffer_square.ref')
    end
  end

end




=begin

  def initialize(bk_file)
    @bk_file = bk_file
  end

  def save(filename)
    write_to_buffer
    save_buffer(filename)
  end

  def write_to_buffer
    @buffer = WaveFile::Buffer.new([ ], WaveFile::Format.new(:mono, :pcm_16, 44100))

    header_array = Tools::word_to_byte_array(@bk_file.start_address) +
                     Tools::word_to_byte_array(@bk_file.length) +
                     @bk_file.name.each_byte.to_a

    write_marker(0o10000)
    write_marker(8)
    write_byte_sequence(header_array)
    write_marker(8)
    write_byte_sequence(@bk_file.body)
    write_byte_sequence(Tools::word_to_byte_array(@bk_file.compute_checksum))
    write_marker(256, 256)
  end

=end

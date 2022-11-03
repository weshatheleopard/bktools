# frozen_string_literal: true

require 'bk_file'

RSpec.describe BkFile do
  context "With a zero-filled file" do
    subject do 
      f = BkFile.new
      f.start_address = 0o1000
      f.length = 0o37000
      f.length.times do |i|
        f.body << 0
      end
      f
    end

    it "should compute checksum" do        
      expect(Tools::octal(subject.compute_checksum)).to eq '000000'
    end
  end

  context "With a sequential file" do
    subject do 
      f = BkFile.new
      f.start_address = 0o1000
      f.length = 0o37000
      (f.length / 2).times do |i|
         bytes = Tools::word_to_byte_array(i)
        f.body << bytes[0] << bytes[1]
      end
      f
    end

    it "should compute checksum" do        
      expect(Tools::octal(subject.compute_checksum)).to eq '040621'
    end
  end

end

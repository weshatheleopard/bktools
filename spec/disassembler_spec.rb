# frozen_string_literal: true

require 'assert_value'
$assert_value_options << "--no-canonicalize"

require 'disassembler'

class TestFile
  attr_accessor :start_address
  attr_accessor :length
  attr_accessor :body

  include Disassembler
end

describe TestFile do
  context "With a squential file" do
    subject do 
      f = TestFile.new
      f.start_address = 0o1000
      f.body = []
      f.length = 0o37000
      (f.length / 2).times do |i|
        bytes = Tools::word_to_byte_array(i*8)
        f.body << bytes[0] << bytes[1]
      end
      f
    end

    it "should disassemble without labels" do        
      expect(subject.disassemble).to be_same_value_as(:log => 'spec/no-labels.asm')
    end

    it "should disassemble with labels" do        
      expect(subject.disassemble_with_labels).to be_same_value_as(:log => 'spec/with_labels.asm')
    end
  end
end

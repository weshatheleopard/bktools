require 'mag_reader'

RSpec.describe TapeReader do
  context "Reader with standard tape" do
    subject do 
      TapeReader.new "spec/source_data/tape_regular.wav", 0
    end

    it "should read the tape successfully" do        
      expect(subject.read).to be true
      expect(subject.bk_file.body.to_s).to be_same_value_as(:log => 'spec/result_data/file_data.dat')
    end
  end

  context "Reader with HELP7 tape" do
    subject do 
      TapeReader.new "spec/source_data/tape_help7.wav", 0
    end

    it "should read the tape successfully" do        
      expect(subject.read).to be true
      expect(subject.bk_file.body.to_s).to be_same_value_as(:log => 'spec/result_data/file_data.dat')
    end
  end

end

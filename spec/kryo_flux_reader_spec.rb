require 'kryo_flux_reader'

RSpec.describe KryoFluxReader do
  context KryoFluxReader do
    let :reader do
      KryoFluxReader.new "spec/track.79.0.raw", 0
    end

    let :track do
      reader.convert_track
    end

    it "should convert RAW file to TRK file" do        
      expect(track.fluxes.to_s).to be_same_value_as(:log => 'spec/track.79.0.fluxes')
    end

    it "scan() should detect sync puse length and read track number from the header" do        
      track.scan
      expect(track.sync_pulse_length).to eq 79.5
      expect(track.track_no).to eq 79
    end
  end
end

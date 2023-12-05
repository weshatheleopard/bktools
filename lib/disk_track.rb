require 'wavefile'
include WaveFile

class DiskTrack

  attr_accessor :fluxes, :indices
  attr_accessor :force_sync_pulse_length
  attr_accessor :debuglevel
  attr_accessor :sectors_per_track

  def initialize(debuglevel = 0)
    @debuglevel = debuglevel

    @fluxes = []
    @indices = []
    @track_no = @side = nil
    @sync_pulse_length = nil
    @sectors = {}
  end

  SOUND_FREQUENCY = 22050
  DIVISOR = 10

  # Method for saving track as wav for reviewing it in a sound editor
  def save_as_wav(filename)
    @buffer = Buffer.new([ ], Format.new(:mono, :pcm_16, SOUND_FREQUENCY))
    val = 30000
    fluxes.each_with_index { |v, i|
      round_val = (v.to_f / DIVISOR).to_i
      round_val = 1 if round_val == 0
      round_val.times { @buffer.samples << ((i.even?) ? 30000 : -30000 ) }
    }

    Writer.new("#{filename}.wav", Format.new(:mono, :pcm_8, SOUND_FREQUENCY)) { |writer| writer.write(@buffer) }
  end

  def side_code(bit)
    case bit
    when 0 then "U"
    when 1 then "D"
    else "_"
    end
  end

  def successful_sectors
    (1..self.sectors_per_track).count { |i| sectors[i] && sectors[i].valid? }
  end

  def complete?
    successful_sectors == self.sectors_per_track
  end

  def sectors_read
    sectors.keys.sort
  end

  def sync_pulse_length
    return @force_sync_pulse_length if @force_sync_pulse_length
    @sync_pulse_length
  end

end

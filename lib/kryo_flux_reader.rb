require 'term/ansicolor'
include Term::ANSIColor

require 'mfm_track'

# Read data from track flux file produced by KryoFlux -- https://www.kryoflux.com/

class KryoFluxReader

  def initialize(filename, debuglevel = 0)
    @debuglevel = debuglevel
    @filename = filename
    @stream = nil
    @file_position = 0
    @stream_position = 0
    @indices_array = []
    @flux_hash = {}
  end

  # ==================== KryoFlux File Decoding ==================== #
 
  def >>(fluxes)
    @stream_position += fluxes
    @file_position += (fluxes - 1)
  end
  private :>>

  # Take track file from KryoFlux and convert it to array of track images (arrays of flux lengths).
  # Each item in the track image array corresponds to a single rotation of the floppy disk.
  # Each track image may slightly differ due to hardware issues. We'll look into that later.
  def convert_track
    @stream_position = @file_position = 0
    File.open(@filename, "rb") { |f| @stream = f.read.bytes }

    @track = MfmTrack.new(@debuglevel)
    @flux_hash = {}
    @indices_array=[]

    loop do
      block_type = @stream[@file_position]
      @file_position += 1

      case block_type
      when 0x00..0x07 then
        lsb = @stream[@file_position]
        add_flux((block_type << 8) + lsb, @stream_position)
        self >> 2
      when 0x08 then # NOP1 block, skip 1 byte
        self >> 1
      when 0x09 then # NOP2 block, skip 2 bytes
        self >> 2
      when 0x0A then # NOP3 block, skip 3 bytes
        self >> 3
      when 0x0B then
        raise "OVL16 block currently not supported"
      when 0x0C then # FLUX3 block
        add_flux((@stream[@file_position] << 8) + @stream[@file_position + 1], @stream_position)
        self >> 3
      when 0x0D then
        break if out_of_stream_block
      when 0x0E..0xFF then
        add_flux(block_type, @stream_position)
        self >> 1
      else
        raise "Unknown block type: %02x" % [block_type]
      end
    end

    # All fluxes are now in @flux_hash, all index data in @indices_array

    @track.fluxes = []
    @flux_hash.keys.sort.each { |pos|
      @track.fluxes << @flux_hash[pos]
      if @indices_array.include?(pos) then
        @track.indices << @track.fluxes.size
      end
    }

    @track
  end

  def add_flux(val, stream_position)
    debug(20) { "#{stream_position} => #{val}" }
    @flux_hash[stream_position] = val
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

      @indices_array << stream_position

      debug(10) {
        "Index signal data".blue.bold +
          "\n  * Stream position of index       : " + stream_position.to_s.bold +
          "\n  * Current reader stream position : " + @stream_position.to_s.bold +
          "\n  * Sample Counter since last flux : " + sample_counter.to_s.bold +
          "\n  * Index Clock value              : " + index_counter.to_s.bold
      }
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

      debug(1) { "KryoFlux device info".magenta + "\n  * [#{str}] (#{sz})" }
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
             (@stream[@file_position + 1] << 8) |
             (@stream[@file_position + 2] << 16) |
             (@stream[@file_position + 3] << 24)
    @file_position += 4
    dword
  end

  def self.convert_disk(dir, debuglevel = 0, fullscan = false)
    full_path = Pathname.new(dir).realpath
    pattern = full_path.join("*.raw")

    Dir.glob(pattern).sort.each { |filename|
      reader = self.new(filename, debuglevel)
      reader.debug(2) { "Processing: #{filename}".yellow }

      track = reader.convert_track

      if fullscan then
        sync_pulse_length = track.find_sync_pulse_length

        if sync_pulse_length then
          reader.debug(0) { "Track processing: ".white + "success".green }

          track.scan
          track.save(filename)
        else
          reader.debug(0) { "Track processing: ".white + "performing cleanup".yellow}
          track.cleanup(80)
          track.force_sync_pulse_length = nil
          track.read
          if track.complete? then
            reader.debug(0) { "Track processing: ".white + "cleanup successful".green}
            track.save(filename)
          else
            reader.debug(0) { "Track processing: ".white + "fail".red}
          end

        end
      else
        reader.debug(8) { 'Detecting track number and side designation'.blue.bold }

        track.scan
        track.save(filename)
      end
    }
  end

  def debug(msg_level)
    return if msg_level > @debuglevel
    msg = yield
    puts(msg) if msg
  end

end

# f = KryoFluxReader.new('temp/vortex32.0.raw');  track =f.convert_track; track.debuglevel = 15
# KryoFluxReader::convert_disk('text1', 1)

require 'wavefile'

require 'term/ansicolor'
include Term::ANSIColor

module TapeSplitter
  DISCREPANCY = 4      # Allowed number of samples difference in pilot squence

  def analyze_tape
    @current_sample_pos = 0
    @prev_len = 0
    @pilot_counter = 0
    @start_pos_candidate = 0
    @split_locations = [ ]
    counter = 0

    reader = WaveFile::Reader.new(@filename, WaveFile::Format.new(:mono, :pcm_16, 44100))
    reader.each_buffer(1024*1024) do |buffer|
      debug 5, "Loaded #{buffer.samples.length.to_s.bold} samples"

      buffer.samples.each { |c|
        @current_sample_pos += 1

        if (c > 0) ^ @invert_waveform then
          counter += 1
        else
          if counter != 0 then
            analyze_impulse(counter)
            counter = 0
          end
        end
      }
    end

    @split_locations << @start_pos_candidate
    @split_locations
  end

  def analyze_impulse(len)
    # If this bit is about as long as the previous one, this can be the header pilot sequence.
    # Let's count how long it is.
    if (len - @prev_len).abs < DISCREPANCY then
      @pilot_counter += 1
    else
      # Discrepancy too large. Let's see if it's an accident or an actual start marker.
      if (@pilot_counter > 0o5000) && (len > (3 * @prev_len)) then  # So it is an actual start marker.
        debug 8, "Pilot sequence detected at ##{@start_pos_candidate.to_s.bold}-#{@current_sample_pos.to_s.bold}"

        @split_locations << @start_pos_candidate
      end  # Just an accident. Start over.

      @pilot_counter = 0
      @start_pos_candidate = @current_sample_pos
    end

    @prev_len = len
  end

  # Split a single wav file containing the entire tape into multiple
  # WAV files each containing and individual BK file recording.
  def split_tape
    split_locations = analyze_tape

    # Now proceed to actually split the file

    position_in_file = 0
    piece_start_location  = 0
    current_write_buffer = make_write_buffer()

    reader = WaveFile::Reader.new(@filename, WaveFile::Format.new(:mono, :pcm_16, 44100))
    reader.each_buffer(1024*1024) do |buffer|
      debug 10, "Loaded #{buffer.samples.length.to_s.bold} samples"

      buffer.samples.each { |c|
        current_write_buffer.samples << c
        position_in_file += 1

        if split_locations.include?(position_in_file) then
          file_name = "#{('0000000000' + piece_start_location.to_s)[-10..-1]}-#{('0000000000' + position_in_file.to_s)[-10..-1]}.wav"
          debug 5, "Saving: #{file_name}"
          WaveFile::Writer.new(file_name, WaveFile::Format.new(:mono, :pcm_16, 44100)) { |writer|
            writer.write(current_write_buffer)
          }

          # Start collectiong a new file
          piece_start_location = position_in_file
          current_write_buffer = make_write_buffer()
        end
      }
    end
  end

  def make_write_buffer()
    WaveFile::Buffer.new([], WaveFile::Format.new(:mono, :pcm_16, 44100))
  end

end

require 'wavefile'

require 'term/ansicolor'
include Term::ANSIColor

module TapeSplitter
  DISCREPANCY = 4      # Allowed number of samples difference in pilot squence

  # Split a wingle wav file containing the entire tape into multiple
  # WAV files each containing and individual BK file recording.
  def split_tape
    convert_file_to_legths if @wavelengths_hash.nil?

    prev_len = 0
    counter = 0

    start_pos_candidate = 0
    split_locations = [ ]

    @wavelengths_hash.each_pair { |position, len|
      # If this bit is about as long as the previous one, this can be the header pilot sequence.
      # Let's count how long it is.
      if (len - prev_len).abs < DISCREPANCY then
        counter += 1
      else
        # Discrepancy too large. Let's see if it's an accident or an actual start marker.
        if (counter > 0o5000) && (len > (3 * prev_len)) then  # So it is an actual start marker.
          debug 8, "Pilot sequence detected at ##{start_pos_candidate.to_s.bold}-#{position.to_s.bold}"

          split_locations << start_pos_candidate
        end  # Just an accident. Start over.

        counter = 0
        start_pos_candidate = position
      end

      prev_len = len
    }

    split_locations << start_pos_candidate

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

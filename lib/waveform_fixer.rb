require 'wavefile'

module WaveformFixer
  MIN_CORRECTION = 5000

  # This modiule contains experimental code for MagReader the is intended to repair files
  #   that were imperfectly read from the tape (with offset reading head, etc.)
  # You should understand what you're doing to use this!

  # This method fixes the "floating zero-level line" problem, where impulses happen to be floating up and down.
  # After calling this method, the centerline will be straihtened and all impulses will be 0-centered.
  def straighten()
 #FIXME
    original_buffer = nil

    reader = WaveFile::Reader.new(@filename, WaveFile::Format.new(:mono, :pcm_16, 44100))
    reader.each_buffer(1024*1024*1024) do |buffer|
      debug 5, "Loaded #{buffer.samples.length.to_s.bold} samples"
      original_buffer = buffer
    end

    min = nil
    max = nil
    max_position = min_position = nil
    current_state = :uptick
    prev = 0

    # This is where offset values will be stored. If needs be, this buffer can be saved.
    offset_buffer = WaveFile::Buffer.new([ 0 ] * original_buffer.samples.size, WaveFile::Format.new(:mono, :pcm_16, 44100))

    original_buffer.samples.each_with_index { |v, i|
      if v > 31000 then v = 31000
      elsif v < -31000 then v = -31000
      end

      case current_state
      when :uptick then
        if v >= prev then
          max = v
        else
          min = v
          max_position = i - 1
          current_state = :downtick
        end
      when :downtick then
        if v <= prev then
          min = v
        else
          min_position = i - 1
          center_waveform(offset_buffer, max, min, max_position, min_position)
          max = v
          current_state = :uptick
        end
      end
      prev = v
    }

    fill_gaps(offset_buffer)

    corrected_buffer = WaveFile::Buffer.new([ 0 ] * original_buffer.samples.size, WaveFile::Format.new(:mono, :pcm_16, 44100))
    corrected_buffer.samples.each_with_index { |v, i|
      corrected_value = original_buffer.samples[i] - offset_buffer.samples[i]

      if corrected_value > 0o77770 then corrected_value = 0o77770
      elsif corrected_value < -0o77770 then corrected_value = -0o77770
      end

      corrected_buffer.samples[i] = corrected_value
    }

    # Save the centerline offset buffer (so you can see how adjustment was applied)
    WaveFile::Writer.new("__offset.wav", WaveFile::Format.new(:mono, :pcm_16, 44100)) { |writer| writer.write(offset_buffer) }

    # Save the corrected waveform
    WaveFile::Writer.new("__straightened.wav", WaveFile::Format.new(:mono, :pcm_16, 44100)) { |writer| writer.write(corrected_buffer) }

    corrected_buffer
  end

  def center_waveform(offset_buffer, max_value, min_value, max_position, min_position, min_correction = nil)
    return if max_value.nil? || min_value.nil?

    min_correction ||= MIN_CORRECTION

    amplitude = (max_value - min_value)
    return if amplitude < min_correction  # Ignore small irregularities

    dy = max_value - (amplitude / 2)  # Maximum ideally should be at (amplitude / 2)

    debug 40, "Adjusting centerline by #{dy} from #{max_position} to #{min_position}".red
    max_position.upto(min_position) { |pos| offset_buffer.samples[pos] = dy }
  end

  def fill_gaps(offset_buffer)
    state = :no_gap
    gap_start = gap_end = value_at_gap_start = value_at_gap_end = nil
    prev = 0

    offset_buffer.samples.each_with_index { |v, i|
      case state
      when :no_gap then
        if v == 0 then
          state = :gap
          gap_start = i
          value_at_gap_start = prev
        end
      when :gap
        if v != 0 then # Gap is over
          state = :no_gap
          gap_end = i
          value_at_gap_end = v

          if gap_start then
            dy = value_at_gap_end - value_at_gap_start
            dx = gap_end - gap_start
            k = dy.to_f / dx

            gap_start.upto(gap_end) { |i|
              offset_buffer.samples[i] = (value_at_gap_start + (i - gap_start) * k).to_i
            }
          end

        end
      end
      prev = v
    }
  end

  # Even more experimental method to fix poorly read sync bits after "1"-bits

=begin
  def fix_sync
    # * When the value becomes negative, skip 14 pulses (the length of "1")
    # * Find max value after that
    # * If max is negative, move it to be positive

    i = 0

    while true do
      while (@buffer.samples[i] && (@buffer.samples[i] > 0)) do
        i += 1
      end
      break if @buffer.samples[i].nil?

      hsh = {}

      while (@buffer.samples[i] && (@buffer.samples[i] <= 0)) do
        hsh[i] = @buffer.samples[i]
        i += 1
      end
      break if @buffer.samples[i].nil?
      max = nil

      if hsh.size > 20 then
        keys = hsh.keys.sort[15...-1]
        keys.each_with_index { |x|
          if (hsh[x-1] < hsh[x]) && (hsh[x+1] < hsh[x]) && (hsh[x] > -25000) then
            max = x
            break
          end
        }
      end  

      if max && @buffer.samples[max] < 0 then
        @buffer.samples[max] = 32500
      end

    end

    WaveFile::Writer.new("fixed.wav", WaveFile::Format.new(:mono, :pcm_16, 44100)) { |writer| writer.write(@buffer) }

  end
=end

end

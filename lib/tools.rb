# Miscellaneous helper methods

module Tools

  def self.bytes2words(input_array)
    word_array = []

    arr = input_array.dup
    sz = arr.size
    sz += 1 if sz.odd?
    sz = sz / 2

    sz.times do
      b0 = arr.shift
      b1 = arr.shift || 0
      bb = bytes2word(b0, b1)
      word_array << octal(bb)
    end
    word_array
  end

  def self.bytes2word(b_low, b_high)
    (b_high << 8) | b_low
  end

  def self.octal(bb)
    bb.to_s(8).rjust(6, '0')
  end

  def self.octal_byte(b)
    b.to_s(8).rjust(3, '0')
  end

  def self.word_to_byte_array(word)
    [ word & 0o377, (word & 0o177400) >> 8 ]
  end

  def self.read_octal(str)
    str.to_i(8)
  end

  def self.adc(val)
    if val > 0o177777 then
      val = val - 0o200000 + 1 # 16-bit cutoff + ADC
    else
      val
    end
  end

  def self.checksum(arr)
    arr.inject(0) { |cksum, byte| Tools::adc(cksum + byte) }
  end

  def self.rollover(val)
    if (val > 0o177777) then
      val -= 0o200000
    else
      val
    end
  end

  def self.byte2char(byte)
    byte_out = case byte
               when (0..31) then 46
               when 0177 then 46
               when 0240 then 191 # Pi
               when 0241 then 137
               when 0242 then 191 # Heart
               when 0243 then 131
               when 0244 then 178
               when 0245 then 134
               when 0246 then 132
               when 0247 then 160
               when 0250 then 184 # Not quite...
               when 0251 then 191 # Spade
               when 0252 then 130
               when 0253 then 136
               when 0254 then 186
               when 0255 then 191 # Arrow down
               when 0256 then 138
               when 0257 then 161
               when 0260 then 135
               when 0261 then 191 # Arrow left
               when 0262 then 138 # Not quite...
               when 0263 then 191 # Arrow up
               when 0264 then 191 # Spades
               when 0265 then 128
               when 0266 then 161 # Not quite...
               when 0267 then 129
               when 0270 then 191 # Clubs
               when 0271 then 133
               when 0272 then 188
               when 0273 then 128 # Not quite...
               when 0274 then 185
               when 0275 then 175
               when 0276 then 191 # Arrow right
               when 0277 then 145
               else byte
               end

    byte_out.chr
  end

  def self.crc_ccitt(byte_array)
    crc = 0xFFFF

    byte_array.each { |b|
      crc ^= (b << 8)
      8.times { crc = ((((crc & 0x8000)!=0) ? ((crc << 1) ^ 0x1021) : (crc << 1)) & 0xFFFF) }
    }

    return crc & 0xFFFF
  end

end

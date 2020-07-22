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
    (byte < 32) ? '.' : byte.chr
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

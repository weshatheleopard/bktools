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

               when 0o001 then 0x2190 # Leftwards arrow

               when 0o003 then 0x2912 # Upwards arrow to bar
               when 0o004 then 0x2913 # Downwards arrow to bar
               when 0o005 then 0x21b5 #enter
               when 0o006 then 0x21e4 # Leftwards Arrow To Bar
               when 0o007 then 0x21e4 # Rightwards Arrow To Bar

               when 0o010 then 0x21f7 # Leftwards Arrow With Vertical Stroke
               when 0o011 then 0x2192 # Rightwards Arrow
               when 0o012 then 0x2191 # Upwards Arrow
               when 0o013 then 0x2193 # Downwards Arrow
               when 0o014 then 0x2b66 # Arrow up left
               when 0o015 then 0x2b67 # Arrow up right
               when 0o016 then 0x2b68 # Arrow down right
               when 0o017 then 0x2b69 # Arrow down left

               when 0o044 then 0x00a4
               when (0o40..0o176) then byte
               when 0o177 then 0x25a0

               when 0o240 then 0x03C0
               when 0o241 then 0x2534
               when 0o242 then 0x2665 # Heart
               when 0o243 then 0x2510
               when 0o244 then 0x2561
               when 0o245 then 0x251c
               when 0o246 then 0x2514
               when 0o247 then 0x2550
               when 0o250 then 0x2564

               when 0o251 then 0x2660
               when 0o252 then 0x250c
               when 0o253 then 0x252c
               when 0o254 then 0x2568
               when 0o255 then 0x2193 # Arrow down
               when 0o256 then 0x253c # Single crossed lines
               when 0o257 then 0x2551 # Dual vertical line

               when 0o260 then 0x2524
               when 0o261 then 0x2190 # Arrow left
               when 0o262 then 0x256c # Double crossed lines
               when 0o263 then 0x2191 # Arrow up
               when 0o264 then 0x2663 # Spades
               when 0o265 then 0x2500 # Single horizontal line
               when 0o266 then 0x256b
               when 0o267 then 0x2502 # Single vertical line

               when 0o270 then 0x2666 # Clubs
               when 0o271 then 0x2518
               when 0o272 then 0x256a
               when 0o273 then 0x2565
               when 0o274 then 0x2567
               when 0o275 then 0x255e
               when 0o276 then 0x2192 # Arrow right
               when 0o277 then 0x2592

               when 0o300 then 0x044e
               when 0o301 then 0x0430
               when 0o302 then 0x0431
               when 0o303 then 0x0446
               when 0o304 then 0x0434
               when 0o305 then 0x0435
               when 0o306 then 0x0444
               when 0o307 then 0x0433

               when 0o310 then 0x0445
               when 0o311 then 0x0438
               when 0o312 then 0x0439
               when 0o313 then 0x043a
               when 0o314 then 0x043b
               when 0o315 then 0x043c
               when 0o316 then 0x043d
               when 0o317 then 0x043e

               when 0o320 then 0x043f
               when 0o321 then 0x044f
               when 0o322 then 0x0440
               when 0o323 then 0x0441
               when 0o324 then 0x0442
               when 0o325 then 0x0443
               when 0o326 then 0x0436
               when 0o327 then 0x0432

               when 0o330 then 0x044c
               when 0o331 then 0x044b
               when 0o332 then 0x0437
               when 0o333 then 0x0448
               when 0o334 then 0x044d
               when 0o335 then 0x0449
               when 0o336 then 0x0447
               when 0o337 then 0x044a

               when 0o340 then 0x042e
               when 0o341 then 0x0410
               when 0o342 then 0x0411
               when 0o343 then 0x0426
               when 0o344 then 0x0414
               when 0o345 then 0x0415
               when 0o346 then 0x0424
               when 0o347 then 0x0413

               when 0o350 then 0x0425
               when 0o351 then 0x0418
               when 0o352 then 0x0419
               when 0o353 then 0x041a
               when 0o354 then 0x041b
               when 0o355 then 0x041c
               when 0o356 then 0x041d
               when 0o357 then 0x041e

               when 0o360 then 0x041f
               when 0o361 then 0x042f
               when 0o362 then 0x0420
               when 0o363 then 0x0421
               when 0o364 then 0x0422
               when 0o365 then 0x0423
               when 0o366 then 0x0416
               when 0o367 then 0x0412

               when 0o370 then 0x042c
               when 0o371 then 0x042b
               when 0o372 then 0x0417
               when 0o373 then 0x0428
               when 0o374 then 0x042d
               when 0o375 then 0x0429
               when 0o376 then 0x0427
               when 0o377 then 0x042a

               else 46
               end

    byte_out.chr('UTF-8')
  end

  def self.crc_ccitt(byte_array)
    crc = 0xFFFF

    byte_array.each { |b|
      crc ^= (b << 8)
      8.times { crc = ((((crc & 0x8000)!=0) ? ((crc << 1) ^ 0x1021) : (crc << 1)) & 0xFFFF) }
    }

    return crc & 0xFFFF
  end

  def self.print_char_table
    16.times { |x|
      16.times { |y|
        putc Tools::byte2char(y * 16 + x)
        putc ' '
      }
      puts
    }
  end

  def self.rom2bin(filename)
    input_data = File.open(filename, 'rb') { |f| f.read }

    if input_data.bytesize != 8194
      puts "Wrong ROM data size: expected 8194, got #{input_data.bytesize}".red
      return
    end

    address_ranges = [ '160000-177777', '140000-157777', '120000-137777', '100000-117777',
                       '060000-077777', '040000-057777', '020000-037777', '000000-017777']
    range = address_ranges[input_data.getbyte(-2)]
    puts 'ROM address range: '.green + range.yellow

    output_data = input_data[0..-3].each_byte.reverse_each.
                    each_slice(2).collect { |s| s.reverse }.flatten.
                    map { |b| (255 - b.ord).chr }

    File.open(filename + ".(#{range}).bin", 'wb') { |f| f.write(output_data.pack('C*') }
  end

end

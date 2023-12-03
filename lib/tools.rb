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
               when (0..037) then 46
               when (040..0176) then byte
               when 0177 then 0x25a0

               when 0240 then 0x3C0
               when 0241 then 0x2534
               when 0242 then 0x2665 # Heart
               when 0243 then 0x2510
               when 0244 then 0x2561
               when 0245 then 0x251c
               when 0246 then 0x2514
               when 0247 then 0x2550
               when 0250 then 0x2564

               when 0251 then 0x2660
               when 0252 then 0x250c
               when 0253 then 0x252c
               when 0254 then 0x2568
               when 0255 then 0x2193 # Arrow down
               when 0256 then 0x253c # Single crossed lines
               when 0257 then 0x2551 # Dual vertical line

               when 0260 then 0x2524
               when 0261 then 0x2190 # Arrow left
               when 0262 then 0x256c # Double crossed lines
               when 0263 then 0x2191 # Arrow up
               when 0264 then 0x2663 # Spades
               when 0265 then 0x2500 # Single horizontal line
               when 0266 then 0x256b
               when 0267 then 0x2502 # Single vertical line

               when 0270 then 0x2666 # Clubs
               when 0271 then 0x2518
               when 0272 then 0x256a
               when 0273 then 0x2565
               when 0274 then 0x2567
               when 0275 then 0x255e
               when 0276 then 0x2192 # Arrow right
               when 0277 then 0x2592

               when 0300 then 0x044e
               when 0301 then 0x0430
               when 0302 then 0x0431
               when 0303 then 0x0446
               when 0304 then 0x0434
               when 0305 then 0x0435
               when 0306 then 0x0444
               when 0307 then 0x0433

               when 0310 then 0x0445
               when 0311 then 0x0438
               when 0312 then 0x0439
               when 0313 then 0x043a
               when 0314 then 0x043b
               when 0315 then 0x043c
               when 0316 then 0x043d
               when 0317 then 0x043e

               when 0320 then 0x043f
               when 0321 then 0x044f
               when 0322 then 0x0440
               when 0323 then 0x0441
               when 0324 then 0x0442
               when 0325 then 0x0443
               when 0326 then 0x0436
               when 0327 then 0x0432

               when 0330 then 0x044c
               when 0331 then 0x044b
               when 0332 then 0x0437
               when 0333 then 0x0448
               when 0334 then 0x044d
               when 0335 then 0x0449
               when 0336 then 0x0447
               when 0337 then 0x044a

               when 0340 then 0x042e
               when 0341 then 0x0410
               when 0342 then 0x0411
               when 0343 then 0x0426
               when 0344 then 0x0414
               when 0345 then 0x0415
               when 0346 then 0x0424
               when 0347 then 0x0413

               when 0350 then 0x0425
               when 0351 then 0x0418
               when 0352 then 0x0419
               when 0353 then 0x041a
               when 0354 then 0x041b
               when 0355 then 0x041c
               when 0356 then 0x041d
               when 0357 then 0x041e

               when 0360 then 0x041f
               when 0361 then 0x042f
               when 0362 then 0x0420
               when 0363 then 0x0421
               when 0364 then 0x0422
               when 0365 then 0x0423
               when 0366 then 0x0416
               when 0367 then 0x0412

               when 0370 then 0x042c
               when 0371 then 0x042b
               when 0372 then 0x0417
               when 0373 then 0x0428
               when 0374 then 0x042d
               when 0375 then 0x0429
               when 0376 then 0x0427
               when 0377 then 0x042a

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

end

# Wrapper class that allows us to track which position on a track a particular bit came from
class BitStream
  attr_reader :size

  def initialize
    @hash = {}
    @size = 0
  end

  def push(ptr, bit)
    ptr = ptr - 1
    @size += 1
    if @hash.has_key?(ptr) then
      @hash[ptr] += bit
    else
      @hash[ptr] = bit
    end
  end

  def to_s
    return nil if @hash.nil? || @hash.empty?
    hash_keys = @hash.keys.sort

    # The way we create bitstream, first bit is always garbage as it is only needed to base fluxes off.
    first_bit = @hash[hash_keys.first]
    s = if (first_bit.size == 1) then ''
        else first_bit[1..-1]
        end

    hash_keys.shift
    hash_keys.each{ |k| s << @hash[k] }
    s
  end

  def to_bytes
    bytes = {}
    keys = @hash.keys.sort
    prev_key = keys.first
    byte = ''
    bits = ''
    correction_flag = true

    loop do
      case bits.size
      when 0 then
        key = keys.shift
        bits = @hash[key]
        break if bits.nil?
        bits = bits.dup
      else
        byte << bits.slice!(0)

        if correction_flag then
          correction_flag = false
          byte = ''
        end

        if byte.size == 8 then
          bytes[prev_key] = byte
          prev_key = keys.first
          byte = ''
        end
      end
    end

    return bytes
  end

  def display(track = nil)
    fluxes = nil
    bytes = self.to_bytes

    arr_keys = bytes.keys.sort

    arr_keys.each_index { |i|
      pos = arr_keys[i]

      if track then
        endpos = arr_keys[i + 1]

        if endpos then endpos = endpos - 1
        else endpos = pos + 4
        end

        slice = []
        pos.upto(endpos) { |i| slice << track.fluxes[i] }
        fluxes = slice.compact.inspect
      end

      v = bytes[pos]
      b = v.gsub('o', '0').to_i(2)

      puts "%10i: | %8s | %02x | %03o | %1s | %s " % [ pos, v, b, b, Tools::byte2char(b), fluxes.to_s ]
    }
  end
end

# Wrapper class that allows us to track which position on a track a particular bit came from
class BitStream
  attr_reader :size

  def initialize
    @hash = {}
    @size = 0
  end

  def push(ptr, bit)
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

  end
end

class BkFile

  attr_accessor :start_address
  attr_accessor :length
  attr_accessor :body
  attr_accessor :name
  attr_accessor :checksum

  def initialize
    @body = []
  end

  def display(options = {})
    puts "File name:     [#{(name + ' ' * 16)[0...16]}]"
    puts "Start address: #{Tools::octal(self.start_address)}"
    puts "Data length:   #{Tools::octal(self.length)}"

    count = 0
    b0 = b1 = nil
    str = ''

    length.times do |i|
      c = body[i]

      if b0.nil? then
        b0 = c
      else
        b1 = c
      end

      c = '.' if c < 32 
      str << c    

      if (count % 8) == 0 then
        print str, "\n", Tools::octal(start_address + count), ": "
        str = ''
      end


      if b0 && b1 then
        print Tools::octal(Tools::bytes2word(b0, b1)), " "
        b0 = b1 = nil
      end
      
      count += 1

    end

    puts    
   
    # Mind the odd start address... there are some quirks there. But, doesnt matter ATM   
#    sz.times do |i|
 #     puts "#{}: #{}"
  #    current_address += 2
   # end
    # Mind odd lengths    

  end

  def compute_checksum
    cksum = 0
    body.each { |byte|
      cksum += byte
      if cksum > 0o177777 then
        cksum = cksum - 0o200000 + 1 # 16-bit cutoff + ADC
      end
    }
    cksum
  end

  def validate_checksum
    checksum == compute_checksum
  end

end

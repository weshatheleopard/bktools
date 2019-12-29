class Help7Block
  attr_accessor :number
  attr_accessor :start_address
  attr_accessor :length
  attr_accessor :body
  attr_accessor :checksum
  attr_accessor :owner_file_checksum

  def initialize
    self.body = []
  end

  def compute_checksum
    Tools::checksum(body)
  end

  def validate_checksum
    checksum == (owner_file_checksum + compute_checksum)
  end
end

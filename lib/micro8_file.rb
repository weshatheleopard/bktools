require 'bk_file'

class Micro8File < BkFile

  def convert_to_txt
    # Return nothing if the file is not a Micro8 file
    return nil unless [016002, 010001].include?(start_address)

    result = ''

    body.each { |b|
      if b < 9 then
        result << ' ' * b
      else
        result << b.chr
      end
    }

    result
  end

end

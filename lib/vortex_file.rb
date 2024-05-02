require 'bk_file'

class VortexFile < BkFile

  def convert_to_txt
    result = ''

    body.each { |b|
      if b == 0 then
        result << "\n"
      else
        result << b.chr
      end
    }

    result
  end

end

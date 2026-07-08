require 'bk_file'

class VortexFile < BkFile

  def convert_to_txt
    body.collect{ |b| (b == 0) ? "\n" : b.chr }.join
  end

end

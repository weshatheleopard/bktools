module BkImage

  attr_accessor :image_header_length

  def save_as_bmp(width = 256)
    height = body.size / (width / 4)
    # BMP code with heavy influence from @Papierkorb - https://gist.github.com/Papierkorb/019ef4b330923175db4a7e6e54f4fb41
    File.open("#{safe_name}-#{width}.bmp", "wb") { |f|
      header_size = 54
      bitmap_size = width * height * 4
      file_size = bitmap_size + header_size

      f << [ # ---------- BMP header
             "BM",        # format code
             file_size,   # u32
             0,           # 2 x u16, reserved
             header_size, # u32
             # ---------- DIB header
             40,          # u32, header size
             width,       # i32
             -height,     # i32
             1,           # u16, # of planes
             32,          # u16, bits per pixel
             0,           # u32, comression method (none)
             bitmap_size, # u32
             0,           # i32, pixels per meter H
             0,           # i32, pixels per meter V
             0,           # u32, colors in palette
             0,           # u32, important colors in palette
           ].pack("A2l<l<l<L<l<l<S<S<l<l<L<L<l<l<")

      height.times do |y|
        str = []
        64.times do |x|
          byte = @body[64 * y + x + (@image_header_length || 0)]

          break if byte.nil? # Bail out if we ran out of data

          4.times do
            case byte & 3
            when 1 then str << 0x000000FF # BLUE
            when 2 then str << 0x0000FF00 # GREEN
            when 3 then str << 0x00FF000F # RED
            when 0 then str << 0x00000000
            end

            byte = byte >> 2
          end

        end

        f << Array(str).pack("l<*")
      end
    }
  end

end

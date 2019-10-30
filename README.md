# bktools
All kinds of tools for BK-0010 (my personal project open for public to see)


## BK-0010 tape format

Unlike some other renditions, this has been derived from the actual BK-0010 firmware.

Logical "0":

```
       23d
     +-----+
     ¦ 11  ¦
0 ---+-----+-----+---
           ¦ 00  ¦
           +-----+
             22d
```

Logical "1":

```
          51d
     +----------+
     ¦          ¦
     ¦    01    ¦
0 ---+----------+----------+---
                ¦     10   ¦
                ¦          ¦
                +----------+
                     51d
```

Data bit sequence:
```
{
  * Data bit ("0" or "1")
  * Sync bit ("0")
}
```
Byte sequence:
```
{
  * Bit #0 (LSB)
  * Bit #1
  * Bit #2
  * Bit #3
  * Bit #4
  * Bit #5
  * Bit #6
  * Bit #7 (MSB)
}
```
Marker sequence (impulse_count, first_impulse_length || 0):
```
{
  * "possibly long 0" (first_impulse_length + 23d / first_impulse_length + 22d)
  * (impulse_count - 1) * "0" (23d / 22d)
  * "long 1" (105d / 100d)
  * synchro "1" (51d / 51d)
  * synchro "0" (24d / 22d)
}
```
File sequence :
```
{
  * marker sequence(4096d, 0)  - pilot marker
  * marker sequence(8d, 0)     - header marker
  * byte sequence              - header data: address (2 bytes) + length (2 bytes) + file name (16d bytes)
  * marker sequence(8d, 0)     - data marker
  * byte sequence              - array_data ("length" bytes)
  * byte sequence              - checksum (2 bytes)
  * marker(256d, 256d)         - trailer pilot
}
```
## Reading data from a WAV file

```
require 'mag_read' ; m = MagRead.new('name.wav', 50); m.read
```
## Writing data to a WAV file

```
require 'mag_write' ; writer = MagWrite.new(bk_file); writer.write('some_filename.wav')
```

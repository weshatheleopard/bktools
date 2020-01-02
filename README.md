# bktools
All kinds of tools for BK-0010 (my personal project open for public to see)


## BK-0010 tape format

Unlike some other renditions, this has been derived from the actual BK-0010 firmware.

The code that supports this format is located in the computer's ROM. No additional software is required to handle it.

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
File sequence:
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

## A non-standard tape format 'HELP7'

This format was supported by a number of application programs. It splits the file into multiple "blocks", each having their own independent checksum, which allows erroneous blocks from one copy of the file to be picked up from another copy. Also this format did not use sync bits, but instead utilized pulses of warying length, each encoding 2-bit "nibbles"; shorter impulses corresponded to the nibbles that appeared the most in a block. That led to further speeding up reading/writing.

File header completely matched the standard file header, which allowed the file names to be displayed just fine when reviewing the tape.

File name:
```
{
  * Bytes 0-12: File name
  * Byte 13:    '&' (38d, 0o46) - marker of 'HELP7' format
  * Byte 14-15: length of HELP7 block. The format supported blocks of diffrent length, but in reality length of 256d (0o400) was seemingly the only one ever used.
}

```
Block sequence
```
{
  * marker sequence(50d, 0)    - block marker
  * marker sequence(9d, 32d)   - block header marker
  * byte sequence              - block header data: nibble mapping (1 byte) + block number (1 byte, 1-based) + block checksum (2 bytes)
  * marker sequence(35d, 0)    - block data marker
  * byte sequence              - array_data ("block length" bytes)
}

```
File sequence:
```
{
  * marker sequence(4096d, 0)  - pilot marker
  * marker sequence(8d, 0)     - header marker
  * byte sequence              - header data: address (2 bytes) + length (2 bytes) + file name (16d bytes)
  * marker sequence(255d, 0)   - file marker
  * byte sequence              - file checksum (2 bytes)
  * quick marker sequence (3 pulses of shortened length)
  * block sequence (as needed)
}
```


## Reading data from a WAV file

```
require 'mag_reader' ; m = MagReader.new('name.wav', 50); m.read
```

## Saving read file to disk

```
m.bk_file.save
```

## Load file from the disk

```
f = BkFile.load "some_file_name"
```

## Compare files and print discrepancies

```
f1 = BkFile.load "some_file_name"
f2 = BkFile.load "another_file_name"
f1.compare(f2)
```

## Writing data to a WAV file

```
require 'mag_writer' ; writer = MagWriter.new(bk_file); writer.write('some_filename.wav')
```
## Automatic splitting

In case you have one big WAV image of a magnetic tape with multiple files on it, there's a method that will split such file into a few WAV files corresponding to a standard-format tape file each.

```
require 'mag_reader' ; m = MagReader.new('tape.wav', 50); m.split_tape

```

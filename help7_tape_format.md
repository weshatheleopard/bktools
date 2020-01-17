## A non-standard tape format 'HELP7'

The file is splits into multiple "blocks", each having their own independent checksum. That allows erroneous blocks from one copy of the file to be picked up from another copy. Also, this format did not use sync bits, but instead utilized pulses of varying length, each encoding 2-bit "nibbles"; shorter impulses corresponded to the nibbles that appeared most often in a particular block. That led to further speeding up reading/writing.

File header completely matched the standard file header, which allowed the file names to be displayed just fine when reviewing the tape.

File name:
```
{
  * Bytes 0-12: File name
  * Byte 13:    '&' (38d, 0o46) - marker of 'HELP7' format
  * Byte 14-15: length of HELP7 block. The format supported blocks of diffrent length, but in reality length of 0o400 (256d) was seemingly the only one ever used.
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

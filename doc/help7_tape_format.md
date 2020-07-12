## A non-standard tape format 'HELP7'

The file is split into multiple "blocks", each having their own independent checksum. That allows erroneous blocks from one copy of the file to be picked up from another copy. Also, this format did not use sync bits, but instead utilized pulses of varying length, each encoding 2-bit "nibbles"; shorter impulses corresponded to the nibbles that appeared most often in a particular block. That led to further speeding up reading/writing.

File header completely matched the standard file header, which allowed the file names to be displayed just fine when reviewing the tape.

For definition of `marker sequence` and `byte sequence` see the [description of standard tape format](bk_tape_format.md).

File name:
```
{
  * Bytes 0-12: File name
  * Byte 13:    '&' (38d, 0o46) - marker of 'HELP7' format
  * Byte 14-15: length of HELP7 block in this file(*).
}

```

(*) The format itself supported blocks of varying lengths, but in reality it seems that 0o400 (256d) was the only length ever used.

Block sequence
```
{
  * marker sequence(50d, 0)            - block marker
  * marker sequence(9d, 32d)           - block header marker
  * byte sequence * 4                  - block header data: nibble mapping (1 byte) + block number (1 byte, 1-based) + block checksum (2 bytes)
  * marker sequence(35d, 0)            - block data marker
  * nibble period * (4 * block length) - block data
}

```
Nibble mapping:

```
Bits in byte: 76543210    correspond to the period of length:
              |||||||+---       < 1.5 of sync tone period (most significant bit)
              ||||||+----       < 1.5 of sync tone period (least significant bit)
              |||||+----- 1.5 ... 2.5 of sync tone period (most significant bit)
              ||||+------ 1.5 ... 2.5 of sync tone period (least significant bit)
              |||+------- 2.5 ... 3.5 of sync tone period (most significant bit)
              ||+-------- 2.5 ... 3.5 of sync tone period (least significant bit)
              |+---------       > 3.5 of sync tone period (most significant bit)
              +----------       > 3.5 of sync tone period (least significant bit)
```
File sequence:
```
{
  * marker sequence(4096d, 0)  - pilot marker
  * marker sequence(8d, 0)     - header marker
  * byte sequence * 20d        - header data: address (2 bytes) + length (2 bytes) + file name (16d bytes)
  * marker sequence(255d, 0)   - file marker
  * byte sequence * 2          - file checksum
  {
    * short marker             (3 short pulses)
    * block sequence
  }                            - as many times as neeeded, last block can be shorter than others if needed.
}
```

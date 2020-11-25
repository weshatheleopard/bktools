## BK-0010 tape format

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
  * marker sequence(4096d, 0)   - pilot marker
  * marker sequence(8d, 0)      - header marker
  * byte sequence * 2           - header data: file start address
  * byte sequence * 2           - header data: file length
  * byte sequence * 16d         - header data: file name
  * marker sequence(8d, 0)      - data marker
  * byte sequence * file length - file body data
  * byte sequence * 2           - checksum
  * marker sequence(256d, 256d) - trailer marker
}
```

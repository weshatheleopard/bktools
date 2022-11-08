# bktools
All kinds of tools for BK-0010 (my personal project open for public to see)

[<img src="https://circleci.com/gh/weshatheleopard/bktools.svg?style=svg" alt="CircleCI" />](https://circleci.com/gh/weshatheleopard/bktools)


## Standard (ROM) tape format

Unlike some other renditions, this description has been derived from the analysis of the actual BK-0010 firmware.

The code that supports this format is located in the computer's ROM. No additional software is required to handle it.

[Description of standard tape format](doc/bk_tape_format.md).

## Accelerated tape format "HELP7"

This format was supported by a number of application programs that had to be loaded first.

[Description of HELP7 tape format](doc/help7_tape_format.md).

# Using this tool

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

# Reading floppy disks

Now this toolset supports [reading data from floppy disks](doc/floppy_disks.md).

# Experimental features

## Display file as octal printout
```
bk_file.display

```

## Display file as PDP-11 disassembly

```
bk_file.disassemble

```

### Display labels instead of addresses

```
bk_file.disassemble_with_labels

```

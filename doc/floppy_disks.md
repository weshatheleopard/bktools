## Disk reading

For dloppy disks, the special hardware - [KryoFlux](https://www.kryoflux.com/) is used that scans the floppy disks and saves the exact timings between individual fluxes.

## Reading the RAW file obtained from KryoFlux software

First, the file in KryoFlux's proprietary format is translated into a simple file containing numeric lengths of time between individial fluxes
```
> reader = KryoFluxReader.new("track_filename.raw")
> track = reader.convert_track
```

You can convert the entire disk (collection of tracks) located in the same directory, at once:
```
KryoFluxReader::convert_disk 'some_directory'
```

Once the track is converted, it can be saved for future use
```
> track.save "name_prefix"
```

In order for the reader to learn meaningful track number and side designation and automatically add those to the track name, it needs to read at least one valid sector header on the track. To accomplish that without actually reading the track, "scan track" command can be used:
```
> track.scan
```

Normally KryoFlux track dump contains multiple revolutions, end-to-end. When saving the track, you can tell it to stop saving after a specific flux, if you know that by that flux you've already gotten all the data of interest:
```
> track.save "name_prefix", number_of_fluxes
```

For ease of manual adjustments, the track can be saved with comments stating the sequential number of each flux:
```
> track.save "name_prefix", nil, true
```

Once the track is saved, `raw` files are no longer needed, and `trk` files can be loaded from the disk:
```
> track = MfmTrack.load("complete_file_name.trk")
```

Reader prints multiple diagnostic messages when processing the track. The level of verbosity can be adjusted by setting debuglevel:
```
> track.debuglevel = <value>
```

The data stored on the track can be obtained by issuing the command:
```
> track.read
```

It will process the flux sequence according to MFM format and store the encountered sectors on the `track` object. They can be later obtained from
```
> track.sectors
```

Most of the tracks read just fine, but for some floppies (generally in the area of tacks 30-40) timings may be off. To solve this, MfmTrack has built-in mechanism to "straighten out" the fluxes, and it tends to help in most situations. Generally, the good base pulse value tends to be 80, but 81 sometimes gives better results:
```
> track.cleanup(80)
```

Disk represents a collection of tracks. In order to load all the track images (`.trk` files) from a directory and convert them into actual binary representation of the disk's sectors:
```
> disk = Disk.load("some_directory")
```

Once all the sectors are loaded, the binary image of the entire disk can be saved:
```
> disk.export("disk_image_name")
```

To manually review contents of a sector (if it has been successfuly read, of course):
```
> sector = track.sectors[8]
> sector.display

000000: 010000 040510 052513 040516 053056 052130 020040 020040  ..HAKUNA.VXT
000020: 002473 000003 024034 002613 000000 162760 167363 027351  ;....(....оеямх.
000040: 054126 020124 020040 020040 002476 000005 024034 004177  VXT     >....(.
[...]
000720: 000000 000000 000000 000000 000000 000000 000000 000000  ................
000740: 000000 000000 000000 000000 000000 000000 000000 000000  ................
000760: 000000 000000 000000 000000 000000 000000 000000 000000  ................
```

Or you can view all the sectors available on the track:
```
> track.display
```

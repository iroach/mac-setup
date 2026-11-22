# Speed tests

Disk speed results for my Macs and Tart VMs, measured with [`disk-speed.sh`](disk-speed.sh).

```sh
zsh ~/mac-setup/speed-tests/disk-speed.sh                 # test the disk your home folder is on
zsh ~/mac-setup/speed-tests/disk-speed.sh /Volumes/Ext    # test another disk
zsh ~/mac-setup/speed-tests/disk-speed.sh --quick         # skip the large uncached read
```

It uses [fio](https://github.com/axboe/fio) with the same settings everywhere, so results from different Macs can be compared:

| Test | Settings |
|---|---|
| Sequential write | 1 MB blocks, 10 GB file, 8 requests in flight, fresh random data |
| Sequential read | the same 10 GB file; can be served partly from memory |
| Sequential read, uncached | a file bigger than RAM (RAM + 8 GB), so it's the real disk speed |
| Random 4K | read/write mix, 1 GB file, 32 requests in flight, 30 seconds |

Sequential results are in MB/s; random results in IOPS (operations per second). Higher is better.

## Summary (averages)

| Machine | Seq. write (MB/s) | Seq. read (MB/s) | Seq. read, uncached (MB/s) | Random 4K read (IOPS) | Random 4K write (IOPS) |
|---|--:|--:|--:|--:|--:|
| MacBook Pro, M5 Pro | 5,385 | 13,701 | 13,984 | 28,309 | 28,279 |
| Mac mini, M4 | 3,292 | 3,496 | 3,384 | 15,259 | 15,239 |
| Tart VM on the MacBook Pro, FileVault **off** | 4,704 | 6,655 | 6,147 | 4,598 | 4,601 |
| Tart VM on the MacBook Pro, FileVault **on** | 3,472 | 1,850 | 1,873 | 4,763 | 4,769 |

What it shows:

- The MacBook Pro's SSD is the fastest: about 14 GB/s reads and 5.4 GB/s writes.
- A VM keeps most of the host's sequential write speed, but reads at under half of it, and small random reads and writes are about 6× slower than on the host.
- For large files, the VM is still faster than the Mac mini running directly. For small random I/O (builds, package installs, databases), the Mac mini is 3–4× faster than the VM.
- **Keep FileVault off in VMs.** With it on, the VM's sequential reads are about 3× slower. It makes no difference on the host (Apple silicon encrypts the SSD in hardware either way), and the VM's disk file is already protected by the host's FileVault.

## Machines

| Machine | Model | Details |
|---|---|---|
| MacBook Pro | Mac17,12 | Apple M5 Pro, 24 GB RAM, 1 TB SSD, macOS 27.2.1, FileVault on |
| Mac mini | Mac16,10 | Apple M4, 24 GB RAM, macOS 27.3 |
| Tart VM | – | On the MacBook Pro. Built from Apple's IPSW (`tart create --from-ipsw=latest --disk-size 100`), 4 CPUs, 4 GB RAM, 100 GB disk (raw format), macOS 27.2.1, bridged networking |

## All runs

All runs on 2026-11-21. The average row is the plain average of the runs above it; a dash means that test wasn't run.

### MacBook Pro, M5 Pro

| Run | Seq. write | Seq. read | Seq. read, uncached (32 GB) | Random 4K read | Random 4K write | Notes |
|---|--:|--:|--:|--:|--:|---|
| 1 | 4,887 | 13,837 | – | 27,433 | 27,401 | `--quick`, first version of the script; a VM was running |
| 2 | 5,434 | 13,592 | – | 24,318 | 24,286 | `--quick`; a VM was running |
| 3 | 5,601 | 13,626 | – | 24,707 | 24,664 | `--quick`; a VM was running |
| 4 | 5,616 | 13,748 | 13,984 | 36,777 | 36,766 | full run, no VMs running |
| **Average** | **5,385** | **13,701** | **13,984** | **28,309** | **28,279** | |

Runs 1–3 were made while a VM was running on the same SSD, which probably held back random 4K. Run 4 is the cleanest.

### Mac mini, M4

| Run | Seq. write | Seq. read | Seq. read, uncached (32 GB) | Random 4K read | Random 4K write | Notes |
|---|--:|--:|--:|--:|--:|---|
| 1 | 3,361 | 3,492 | 3,453 | 11,909 | 11,890 | |
| 2 | 3,223 | 3,499 | 3,314 | 18,609 | 18,587 | |
| **Average** | **3,292** | **3,496** | **3,384** | **15,259** | **15,239** | |

### Tart VM, FileVault off

| Run | Seq. write | Seq. read | Seq. read, uncached (12 GB) | Random 4K read | Random 4K write | Notes |
|---|--:|--:|--:|--:|--:|---|
| 1 | 4,709 | 6,480 | 6,101 | 4,302 | 4,303 | |
| 2 | 4,699 | 6,830 | 6,192 | 4,893 | 4,899 | |
| **Average** | **4,704** | **6,655** | **6,147** | **4,598** | **4,601** | |

### Tart VM, FileVault on

| Run | Seq. write | Seq. read | Seq. read, uncached (12 GB) | Random 4K read | Random 4K write | Notes |
|---|--:|--:|--:|--:|--:|---|
| 1 | 3,304 | 1,840 | 1,874 | 4,425 | 4,431 | right after macOS setup |
| 2 | 3,211 | 1,790 | – | 4,888 | 4,894 | `--quick` |
| 3 | 3,900 | 1,919 | 1,871 | 4,976 | 4,981 | a clone of the FileVault-off VM, with FileVault turned on |
| **Average** | **3,472** | **1,850** | **1,873** | **4,763** | **4,769** | |

## For comparison: Blackmagic Disk Speed Test

On the MacBook Pro (host), Blackmagic Disk Speed Test showed **10,811 MB/s write** and **10,008 MB/s read**. Its write number is higher than fio's because Blackmagic writes data that's easier on the SSD; `disk-speed.sh` writes fresh random data every time. Blackmagic can't be used in a VM: it comes from the App Store, and the App Store can't be signed into in a macOS VM.

## Adding results

Run the script a few times on the same machine, with nothing heavy running (in a VM, also nothing heavy on the host). Add each run as a row in the machine's table, update the average row, and copy the averages to the summary.

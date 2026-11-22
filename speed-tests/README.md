# Speed tests

Disk speed results for my Macs and Tart VMs, measured with [`disk-speed.sh`](disk-speed.sh). Every run is in [`results.csv`](results.csv); the summary below shows one run per model.

```sh
zsh ~/mac-setup/speed-tests/disk-speed.sh                 # test the disk your home folder is on
zsh ~/mac-setup/speed-tests/disk-speed.sh /Volumes/Ext    # test another disk
zsh ~/mac-setup/speed-tests/disk-speed.sh --quick         # skip the large uncached read
zsh ~/mac-setup/speed-tests/disk-speed.sh --save          # also add the run to results.csv
```

It uses [fio](https://github.com/axboe/fio) with the same settings everywhere, so results from different Macs can be compared:

| Test | Settings |
|---|---|
| Sequential write | 1 MB blocks, 10 GB file, 8 requests in flight, fresh random data |
| Sequential read | the same 10 GB file; can be served partly from memory |
| Sequential read, uncached | a file bigger than RAM (RAM + 8 GB), so it's the real disk speed |
| Random 4K | read/write mix, 1 GB file, 32 requests in flight, 30 seconds |

Sequential results are in MB/s; random results in IOPS (operations per second). Higher is better.

## Summary

The best-case run for each model, built from `results.csv` by [`summary.sh`](summary.sh): runs with VM and FileVault off are preferred, then full runs over `--quick` ones, then the fastest uncached read. The MacBook Pro has only FileVault-on runs so far, so its row has FileVault on.

<!-- summary:start -->
| Machine | Model | VM | FileVault | Seq. write (MB/s) | Seq. read (MB/s) | Seq. read, uncached (MB/s) | Random 4K read (IOPS) | Random 4K write (IOPS) | Date |
|---|---|---|---|--:|--:|--:|--:|--:|---|
| MacBook Pro | Mac17,12 | False | True | 5,616 | 13,748 | 13,984 | 36,777 | 36,766 | 2026-11-21 |
| Mac mini | Mac16,10 | False | False | 3,361 | 3,492 | 3,453 | 11,909 | 11,890 | 2026-11-21 |
| Tart VM on MacBook Pro | VirtualMac2,1 | True | False | 4,699 | 6,830 | 6,192 | 4,893 | 4,899 | 2026-11-21 |
<!-- summary:end -->

What it shows:

- The MacBook Pro's SSD is the fastest: about 14 GB/s reads and 5.6 GB/s writes.
- A VM keeps most of the host's sequential write speed, but reads at under half of it, and small random reads and writes are about 7× slower than on the host.
- For large files, the VM is still faster than the Mac mini running directly. For small random I/O (builds, package installs, databases), the Mac mini is 2–4× faster than the VM.
- **Keep FileVault off in VMs.** With it on, the VM's sequential reads are about 3× slower (about 1,850 MB/s instead of 6,500; see the FileVault-on VM runs in `results.csv`). It makes no difference on the host (Apple silicon encrypts the SSD in hardware either way), and the VM's disk file is already protected by the host's FileVault.

The Tart VM was built from Apple's IPSW (`tart create --from-ipsw=latest --disk-size 100`) on the MacBook Pro: 4 CPUs, 4 GB RAM, 100 GB disk (raw format), bridged networking. The MacBook Pro has a 1 TB SSD.

## results.csv

One row per run. A blank number means that test wasn't run.

| Column | Meaning |
|---|---|
| `date` | day of the run |
| `machine` | a readable name; the Mac's model name unless `--name` was given |
| `model` | model identifier (`sysctl hw.model`), such as `Mac17,12`; VMs report `VirtualMac2,1` |
| `chip`, `ram_gb`, `macos` | the chip, memory and macOS version the run saw (a VM sees its own RAM) |
| `vm` | `True` when run inside a virtual machine |
| `filevault` | `True` when FileVault was on (`fdesetup status`) |
| `quick` | `True` when the uncached read was skipped (`--quick`, or not enough free space) |
| `seq_write_mbs`, `seq_read_mbs`, `seq_read_uncached_mbs` | sequential results in MB/s |
| `rand_read_iops`, `rand_write_iops` | random 4K results in IOPS |
| `notes` | anything that affected the run, from `--note` |

## Testing another Mac or VM

1. Get the repo on the machine (`~/mac-setup` after `setup.sh`, or `git clone https://github.com/iroach/mac-setup.git`) and switch to a new branch.
2. Quit anything heavy. In a VM, also keep the host quiet.
3. Run the test with `--save`, two or three times:
   ```sh
   zsh ~/mac-setup/speed-tests/disk-speed.sh --save
   zsh ~/mac-setup/speed-tests/disk-speed.sh --save --name "Tart VM on Mac mini" --note "FileVault turned on after setup"
   ```
   Each run appends a row to `results.csv` and rebuilds the summary in this README. The model, VM and FileVault columns are filled in automatically. For a VM, use `--name` to say which Mac it runs on.
4. Check the new rows with `git diff`, then commit and open a pull request.

If the run happened somewhere without the repo (for example a VM you don't want to clone into), copy the `CSV row for results.csv` line the script prints at the end, paste it at the bottom of `results.csv`, and run `zsh ~/mac-setup/speed-tests/summary.sh`.

To remove a bad run, delete its line from `results.csv` and rerun `summary.sh`.

## For comparison: Blackmagic Disk Speed Test

On the MacBook Pro (host), Blackmagic Disk Speed Test showed **10,811 MB/s write** and **10,008 MB/s read**. Its write number is higher than fio's because Blackmagic writes data that's easier on the SSD; `disk-speed.sh` writes fresh random data every time. Blackmagic can't be used in a VM: it comes from the App Store, and the App Store can't be signed into in a macOS VM.

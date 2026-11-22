# Speed tests

Disk and build speed results for my Macs and Tart VMs: disk speed with [`disk-speed.sh`](disk-speed.sh), build speed with [`build-speed.sh`](build-speed.sh) ([below](#build-speed)).

## Disk speed

Measured with [`disk-speed.sh`](disk-speed.sh). Every run is in [`results.csv`](results.csv); the summary below shows one run per model.

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

### Summary

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

### results.csv

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

### Testing another Mac or VM

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

### For comparison: Blackmagic Disk Speed Test

On the MacBook Pro (host), Blackmagic Disk Speed Test showed **10,811 MB/s write** and **10,008 MB/s read**. Its write number is higher than fio's because Blackmagic writes data that's easier on the SSD; `disk-speed.sh` writes fresh random data every time. Blackmagic can't be used in a VM: it comes from the App Store, and the App Store can't be signed into in a macOS VM.

## Build speed

How fast each Mac builds native code, measured with [`build-speed.sh`](build-speed.sh). It builds pinned versions of open-source projects the same way on every Mac and times them. Every run is in [`build-results.csv`](build-results.csv); the summary below shows each machine's best time per project.

```sh
zsh ~/mac-setup/speed-tests/build-speed.sh                      # every project that can run here
zsh ~/mac-setup/speed-tests/build-speed.sh --project openssl    # one project (or --project openssl,sdl)
zsh ~/mac-setup/speed-tests/build-speed.sh --runs 1             # one build per project instead of 3
zsh ~/mac-setup/speed-tests/build-speed.sh --save               # also add the results to build-results.csv
zsh ~/mac-setup/speed-tests/build-speed.sh --start-only         # only the program-start test (about 15 seconds)
```

This is a pilot: it builds several candidate projects so we can see, across 3 or 4 Macs, which one gives the most useful numbers. The best one will become the default.

| Project | Version | What it builds | Needs |
|---|---|---|---|
| `openssl` | 3.5.9 (LTS) | The libraries and `openssl` command (`make build_sw`): C and generated assembly | Command Line Tools |
| `ffmpeg` | 8.1.3 | The libraries and `ffmpeg`/`ffprobe`: a large C codebase plus macOS media frameworks (VideoToolbox, AudioToolbox, AVFoundation in Objective-C). Only what ships with macOS, so Homebrew libraries don't change the build | Command Line Tools |
| `sdl` | 3.4.20 | The SDL3 library: C plus Objective-C Cocoa (AppKit) windowing and Metal code | Command Line Tools, cmake |
| `netnewswire` | mac-7.3.1 | The NetNewsWire Mac app and iOS app (for the simulator), Debug, unsigned: Swift with AppKit, UIKit and SwiftUI | Xcode |
| `ghostty` | 1.4.0 | The Ghostty Mac app, ReleaseFast: a Zig core plus a Swift (AppKit and SwiftUI) app and Metal shaders | Xcode, Zig 0.17.0 (downloaded by the script) |

How it measures:

- Each run starts from a fresh copy of the source and builds with one job per CPU core. Configure (or copying the source) is timed separately and isn't part of the score.
- The score is the **median build time** of the runs (3 by default), in seconds; lower is better. The spread between the fastest and slowest run is printed, so a noisy run shows.
- Sources are downloaded once into `~/Library/Caches/mac-setup/build-speed`, checked against a pinned SHA-256 (taken from the projects' signed releases), so timing never includes the network. NetNewsWire's Swift packages and Ghostty's Zig packages are fetched there once too. Nothing compiled is reused between runs.
- Build folders are deleted however the script ends; the last log for each project stays in `~/Library/Caches/mac-setup/build-speed/logs`.
- If a project can't be set up or fails to build, the script says so and points to its log, and the other projects still run and are saved. It checks for the Command Line Tools first.
- Xcode projects use Xcode even when `xcode-select` points at the Command Line Tools, and are skipped (with the reason) when Xcode isn't installed. Xcode is not installed by `setup.sh`.
- A laptop on battery or in Low Power Mode builds slower; the script warns, and records both.
- **Program-start test.** Every run starts with three quick measurements, each the median of 3 rounds: starting `/usr/bin/true` 1,000 times (ms per program start), compiling an empty C file 200 times (ms per compile), and writing 5,000 small files next to the builds (µs per file). Builds do these thousands of times, so this shows what security software (antivirus, EDR) adds on a Mac, apart from compile speed (see [#17](https://github.com/iroach/mac-setup/issues/17)). They go into every CSV row of the run; `--start-only` runs just these and saves a row with no project.

### Build summary

One row per machine name and CPU count, so a VM run with 4 CPUs and one with 18 get separate rows. Best median build time per project, in seconds, built from `build-results.csv` by [`build-summary.sh`](build-summary.sh). Runs on AC power with Low Power Mode off are preferred. The Start, clang and File columns are the program-start test from the machine's newest run that has it. "–" means it wasn't run there.

<!-- build-summary:start -->
| Machine | Model | Chip | Cores | RAM | VM | Start (ms) | clang (ms) | File (µs) | openssl (s) | ffmpeg (s) | sdl (s) | netnewswire (s) | ghostty (s) | Date |
|---|---|---|---|--:|---|--:|--:|--:|--:|--:|--:|--:|--:|---|
| Mac mini | Mac16,10 | Apple M4 | 10 (4P+6E) | 24 GB | False | 1.00 | 15.8 | 43 | 35.0 | 48.4 | 8.3 | 66.7 | 165.1 | 2026-11-22 |
| MacBook Pro M5 Pro | Mac17,12 | Apple M5 Pro | 18 (6P+12E) | 24 GB | False | – | – | – | 61.9 | 44.4 | 11.8 | 48.6 | – | 2026-11-22 |
| MacBook Pro M1 Max | MacBookPro18,2 | Apple M1 Max | 10 (8P+2E) | 32 GB | False | – | – | – | 50.0 | 54.8 | 10.6 | 102.5 | – | 2026-11-22 |
| MacBook Pro Intel | MacBookPro16,1 | Intel(R) Core(TM) i9-9880H CPU @ 2.30GHz | 16 threads (8 cores) | 16 GB | False | 2.52 | 40.8 | 121 | 68.0 | 71.5 | 17.3 | – | – | 2026-11-22 |
| Apple M5 Pro (Virtual) | VirtualMac2,1 | Apple M5 Pro (Virtual) | 18 virtual | 16 GB | True | 0.98 | 12.6 | 44 | 17.1 | 22.0 | – | – | – | 2026-11-22 |
<!-- build-summary:end -->

First pilot results, on the Mac mini (M4, 3 runs each):

- **OpenSSL** is the steadiest: 34.9 to 35.4 seconds (1.4% spread), with only 5 seconds of configure. Good candidate for the default.
- **FFmpeg** builds for 48 seconds (3.5% spread), but its configure takes another 24 seconds.
- **SDL** builds in only 8 seconds, after 23 seconds of cmake configure: too short to tell Macs apart well. It's the only Command Line Tools project with AppKit code; it may be dropped after the pilot.
- **NetNewsWire** takes 67 seconds for both apps. The first run of a session is about 10% slower (Xcode's shared caches warming up), which the median hides.
- **Ghostty** is the longest at 165 seconds (4.6% spread). It needs Xcode's Metal Toolchain component (about 850 MB): `xcodebuild -downloadComponent MetalToolchain`.

### Choosing the default project

After the pilot runs, pick the project that is:

- **Long enough to be steady, short enough to run often:** about 1 to 3 minutes on the MacBook Pro.
- **Steady:** under about 3% between the fastest and slowest run on a Mac (not a VM).
- **Telling:** the gap between Macs is clear. If every project ranks the Macs the same way, keep the quickest reliable one.
- **Portable:** builds on Apple silicon, Intel and in a VM with no extra tools (the Command Line Tools projects), with an Xcode project as the optional second score.

### build-results.csv

One row per project per run of the script.

| Column | Meaning |
|---|---|
| `date`, `machine`, `model`, `chip`, `ram_gb`, `macos`, `vm` | as in `results.csv` |
| `arch` | `arm64` or `x86_64` |
| `cores`, `p_cores`, `e_cores` | CPU cores (on Intel, threads), and how many are performance and efficiency cores. On Intel, `p_cores` is the physical cores and `e_cores` is blank. In a VM, `cores` is the virtual CPUs |
| `clang`, `xcode` | the Command Line Tools' clang and the Xcode version (blank without Xcode) |
| `power`, `low_power` | `AC` or `battery`, and `True` when Low Power Mode was on |
| `project`, `version` | what was built |
| `jobs`, `runs` | parallel build jobs (one per core) and how many builds |
| `configure_s` | median configure time in seconds (not part of the score) |
| `build_s_median`, `build_s_min`, `build_s_max` | build times in seconds |
| `start_ms`, `clang_ms`, `file_us` | the program-start test: ms per program start, ms per empty clang compile, µs per small file. Blank in rows from before the test existed |
| `notes` | anything that affected the run, from `--note` |

### Testing another Mac and submitting the results

Anyone can submit results; they're added after review. Get the repo (`git clone https://github.com/iroach/mac-setup.git ~/mac-setup`), plug in a laptop and quit anything heavy, then run

```sh
zsh ~/mac-setup/speed-tests/build-speed.sh --submit --name "MacBook Pro M5 Pro"
```

When it finishes, a "Build speed results" issue opens in your browser with the results filled in. Say how the Mac is set up (personal, work-managed with security software, or a VM), add any notes, and select **Create**. Nothing is pushed from the Mac, and you don't need git set up for pushing. A full run with every project takes about 10 to 20 minutes on an M-series Mac; `--project openssl,ffmpeg,sdl` skips the Xcode projects.

To review a submission (maintainers):

1. Check the rows in the issue: the machine name, the numbers, and that nothing identifies a person or organization.
2. Add the **approved** label. The [Import build results](../.github/workflows/import-build-results.yml) action checks every field strictly with [`import-results.py`](import-results.py), adds the rows to `build-results.csv` (with the issue number and the setup answer in `notes`), rebuilds the summary, and opens a pull request that closes the issue. If a row is wrong, it comments on the issue instead.
3. Review and merge the pull request.

To import an issue by hand instead: `gh issue view 42 --json body -q .body | python3 -I speed-tests/import-results.py 42`, then `zsh speed-tests/build-summary.sh`.

`--save` still adds the rows to `build-results.csv` directly, for a Mac where you'll commit them yourself.

### Testing in a VM: security software or not

Security software on a Mac (EDR, antivirus) checks programs and files on the Mac itself, but not inside a virtual machine. Running the test in a Tart VM on the same Mac shows how much that software costs: compare the VM's program-start results and configure times (which run one program at a time, so CPU count matters little) with the Mac's own. See [#17](https://github.com/iroach/mac-setup/issues/17). On the Mac mini, which has no such software, the VM's numbers match the Mac's.

[`vm-build-speed.sh`](vm-build-speed.sh) does this with [Tart](https://tart.run). On each Mac to test:

1. **Get the latest repo.** `cd ~/mac-setup && git pull` (or clone it, as above). Until the build speed test is merged into `main`, use its branch: `git fetch origin && git switch build-speed-test && git reset --hard origin/build-speed-test`.

2. **Install Tart** if `tart --version` doesn't work. `setup.sh` installs it from the Brewfile; by hand, trust the tap first, as `setup.sh` does:
   ```sh
   brew tap openai/tools && brew trust --formula openai/tools/tart && brew install openai/tools/tart
   ```

3. **Have an SSH key.** The script logs in to the VM with `~/.ssh/id_ed25519`. If `ls ~/.ssh/id_ed25519.pub` finds nothing, make one with `ssh-keygen -t ed25519` (press Return for no passphrase, or use one held by the SSH agent).

4. **Test the Mac itself** with the program-start test, so there's something to compare the VM with (about 15 seconds):
   ```sh
   zsh ~/mac-setup/speed-tests/build-speed.sh --start-only --name "MacBook Pro M5 Pro" --submit
   ```
   For a fuller comparison, run `--project openssl,ffmpeg,sdl` instead of `--start-only` (10 to 20 minutes).

5. **Make the VM, once.** This downloads a macOS image of tens of gigabytes (it takes about 35 GB on disk), so allow time and space. It works with any image that has an `admin` user (password `admin`, or set `VM_PASSWORD`), Remote Login and passwordless sudo, as Cirrus Labs' vanilla images do:
   ```sh
   zsh ~/mac-setup/speed-tests/vm-build-speed.sh prepare ghcr.io/cirruslabs/macos-golden-gate-vanilla:latest
   ```
   It saves the VM as `build-speed-base`, with Homebrew, the Command Line Tools and cmake installed and your SSH key added. Company-managed Macs may block VMs or the download; if so, ask IT.

6. **Run the test in the VM.** Each run uses a fresh copy of `build-speed-base` with 4 CPUs and 8 GB, waits a minute for it to settle after starting, and deletes it afterwards. Use the same `--project` as in step 4:
   ```sh
   zsh ~/mac-setup/speed-tests/vm-build-speed.sh run --start-only --name "Tart VM on MacBook Pro M5 Pro" --submit
   ```
   The issue form opens on this Mac, as in step 4. Use the same `--cpu` and `--memory` everywhere (defaults 4 and 8) so VM results compare.

`--submit` needs the issue form and its action on `main`. Until the build speed test is merged, use `--save` in steps 4 and 6 instead, then commit the new rows (with the GitHub noreply address as your git email) and push them to the branch.

When you're done, `tart delete build-speed-base` frees the space; keep it to test again later.

# The One Billion Row Challenge

Zig implementation of the [1brc](https://github.com/gunnarmorling/1brc) challenge.

## Generating a test file

To generate `measurements.txt` file with the 1B rows, follow the instructions from the original repo https://github.com/gunnarmorling/1brc.

## Build

> The project was compiled using the `0.12.0-dev.2254+195eeed2d` version.

```
zig build -Doptimize=ReleaseFast
```

## Run

```
./zig-out/bin/1brc-zig {file_path}

./zig-out/bin/1brc-zig data/weather_stations.csv
```

## Benchmarks

To measure the execution time run:
```
time ./zig-out/bin/1brc-zig measurements.txt > /dev/null
```

To benchmark using `hyperfine`:
```
hyperfine --warmup 1 "./zig-out/bin/1brc-zig measurements.txt"
```

Benchmarks results for `Apple M1 Pro 32MB RAM, 10 CPU Cores`

```
time ./zig-out/bin/1brc-zig measurements.txt > /dev/null

33.64s user
1.71s system
874% CPU
4.044 total
```

```
hyperfine --warmup 1 "./zig-out/bin/1brc-zig measurements.txt > /dev/null"

Benchmark 1: ./zig-out/bin/1brc-zig measurements.txt > /dev/null
  Time (mean ± σ):      4.057 s ±  0.049 s    [User: 33.571 s, System: 1.607 s]
  Range (min … max):    3.997 s …  4.135 s    10 runs
```

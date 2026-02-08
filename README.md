# TypeTest

## Installation
### AUR
todo

## Building

1. Make sure [zig](https://ziglang.org/learn/getting-started/) and [git](https://git-scm.com/install/) are installed and in your [path](https://superuser.com/questions/517894/what-is-the-unix-path-variable-and-how-do-i-add-to-it).
2. Clone and build:
```sh
git clone "https://github.com/jacpa42/typetest"
cd typetest
zig build -Doptimize=ReleaseFast
```

## Usage
The built exe should be located at `zig-out/bin/typetest`:

```sh
~/typetest ❯ ./zig-out/bin/typetest
You need to provide input words via stdin or via a file with --word-file

  -h, --help                  Display this help and exit
  -s, --seed <seed>           Seed to use for rng (default is a random)
  -a, --duration <dur>        Duration of the title screen animation in frames
  -c, --cursor-shape <shape>  Cursor style (default is block): block | beam | underline
  -m, --mode <mode>           Word generation mode (default is random): random | sequential
  -w, --word-file <file>      File to select words from (ignored if stdin is not empty)
  -l, --lowercase             Whether or not to make all words lowercase.
  -b, --blink                 Whether or not the cursor blinks
  -f, --fps <fps>             Desired frame rate for the game (default is 60)
```

Like the above help message says, you need to provide input words. I have a file called `words.txt` in the repo which contains `3000` common English words which you can use (all lower-case).

### grep

As the tool uses `stdin`, it is easy to setup custom tests with tools like grep:

#### No words longer than 6 characters
```sh
export CHAR_LIMIT=6
grep "^.\{0,$CHAR_LIMIT\}\$" words.txt | ./zig-out/bin/typetest
```

#### Only words containing specific characters
```sh
export CHARS=abc
grep -E "^[$CHARS]+\$" words.txt | ./zig-out/bin/typetest
```

Lin is a *lin*ear build system.  Steps are run from top to bottom.

# Getting started

Install the `lin` executable and `lin` nimble package with:

```bash
nimble install https://github.com/iffy/lin
```

Make a `linseed.nim` file:

```nim
import lin

var build = sequence("build", help = "Say hello")
var clean = sequence("clean", help = "Clean up hello", reverse = true)

var name = strVar("name", help = "Name to greet", default = "Bob")
var shout = boolVar("shout", help = "If given, shout")

build.step "hello":
  stdout.write "Hello, "
  stdout.write name.strVal
  if shout.boolVal:
    stdout.write "!"
  stdout.write "\L"

clean.step "hello":
  stdout.write "Goodbye, "
  stdout.write name.strVal
  if shout.boolVal:
    stdout.write "!"
  stdout.write "\L"

build.step "mkfile":
  if existsFile("somedir"/"somefile.txt"):
    skip "Already done"
  createDir "somedir"
  cd "somedir":
    sh "touch", "somefile.txt"

clean.step "mkfile":
  shmaybe "rm", "-r", "somedir"

if isMainModule:
  cli()
```

Try the following:

```sh
lin --help
lin build
lin clean
lin build:hello
lin build --name Alice
lin clean build
lin clean build -l
```

# Details

Go [read the full docs](https://www.iffycan.com/lin/linlib.html), but here's a high level overview of what's included in `import lin`:

| Thing | Description |
|---|---|
| `sequence` | Name a new sequence of steps |
| `strVar` | Define a string variable (which can be seen in the `--help` documentation) |
| `boolVar` | Define a boolean variable |
| `sh` | Run a subprocess, aborting on error |
| `shmaybe` | Run a subprocess, ignoring exit code |
| `cd` | Run a block of code from within another directory |
| `skip` | Abort the current step, but keep running subsequent steps |
| `olderThan` | DEPRECATED: Determine if a set of output files are older than a set of input files |
| `hasNewerSources` | Return true if a rebuild should happen |
| `newerSources` | Return the source files that are newer than the output file |

Other helpful hints:

- Sequences can include other sequences, thus chaining them together.  See the `includes` param.

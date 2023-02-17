import std/algorithm
import std/exitprocs
import std/os; export os
import std/osproc
import std/re
import std/sequtils
import std/streams
import std/strformat
import std/strutils
import std/tables
import std/terminal ; export terminal
import std/times

const hasThreads = compileOption("threads")

type
  UnknownFlag* = object of CatchableError
  DuplicateName* = object of CatchableError
  SkipSignal* = object of CatchableError

  Sequence* = ref object
    lin: Lin
    name: string
    help: string
    reverse: bool
    includes: seq[string]
  
  Step = object
    seqname: string
    name: string
    fn: proc()

  VarKind = enum
    StringVar,
    BooleanVar,

  Variable* = ref object
    name: string
    help: string
    case kind*: VarKind
    of StringVar:
      strVal*: string
    of BooleanVar:
      boolVal*: bool

  Lin = ref object
    sequences: OrderedTableRef[string, Sequence]
    steps: seq[Step]
    variables: OrderedTableRef[string, Variable]
    default_seqs: seq[string]
  
  RunStatus = enum
    resOk,
    resFail,
    resSkip,

const DELIM = "/"

proc fullname*(s:Step):string {.inline.}

proc newLin*():Lin =
  ## Make a new Lin. Typically, you should just use
  ## the singleton built-in to the library. This is mostly
  ## here for testing.
  result = Lin()
  result.variables = newOrderedTable[string, Variable]()
  result.sequences = newOrderedTable[string, Sequence]()

proc sequence*(lin:Lin, name:string, help = "", reverse = false, includes:seq[string] = @[], default = false):Sequence =
  result = Sequence(name: name, lin: lin, help:help, reverse:reverse, includes:includes)
  lin.sequences[name] = result
  if default:
    lin.default_seqs.add(name)

proc allIncludes(lin:Lin, key:string):seq[string] =
  ## Return all the included sequence names (recursively) for a sequence name
  var s = lin.sequences[key]
  for x in s.includes:
    result.add(lin.allIncludes(x))
  result.add(s.includes)

proc seqname*(x:string):string {.inline.} = x.split(DELIM, 1)[0]

iterator expandRanges(lin:Lin, keys:openArray[string]):string =
  for key in keys:
    let parts = key.split("..")
    if parts.len == 1:
      # not a range
      yield key
    elif parts.len == 2:
      # range
      var
        a = parts[0]
        b = parts[1]
      if a == "":
        # ..b
        a = b.seqname
      elif b == "":
        # a..
        b = a.seqname

      var seqs_to_traverse:seq[string]
      seqs_to_traverse.add(a.seqname)
      seqs_to_traverse.add(b.seqname)
      seqs_to_traverse.add(lin.allIncludes(a.seqname))
      seqs_to_traverse.add(lin.allIncludes(b.seqname))

      let steps = if lin.sequences[a.seqname].reverse: lin.steps.reversed() else: lin.steps

      if a.find(DELIM) == -1:
        # a is a sequence name, find the first step
        for step in steps:
          if step.seqname in seqs_to_traverse:
            a = step.fullname
            break
      if b.find(DELIM) == -1:
        # b is a sequence name, find the last step
        for step in steps:
          if step.seqname in seqs_to_traverse:
            b = step.fullname
      
      var started = false
      for step in steps:
        if not started:
          if step.fullname == a:
            started = true
          else:
            continue
        # inside the range
        if step.seqname in seqs_to_traverse:
          yield step.fullname
        if step.fullname == b:
          break
    else:
      raise newException(CatchableError, "Invalid step name: " & key)

proc collectSteps*(lin:Lin, keys:openArray[string]):seq[Step] =
  ## List the steps that will be run
  # Group them by direction
  var
    groups:seq[tuple[reverse:bool, keys:seq[string]]]
  groups.add((reverse:false, keys: newSeq[string]()))
  for key in lin.expandRanges(keys):
    let seqname = key.seqname
    if not lin.sequences.hasKey(seqname):
      raise newException(KeyError, &"No such sequence: {key}")
    let s = lin.sequences[seqname]
    if s.reverse != groups[^1].reverse:
      # new direction
      groups.add((reverse:s.reverse, keys: newSeq[string]()))
    groups[^1].keys.add(key)

  for group in groups:
    var
      whole_seqs:seq[string]
      specific:seq[string]
      toadd:seq[Step]
    for key in group.keys:
      if key.find(DELIM) == -1:
        whole_seqs.add(key)
        if not lin.sequences.hasKey(key):
          raise newException(KeyError, &"No such sequence: {key}")
        whole_seqs.add(lin.allIncludes(key))
      else:
        specific.add(key)

    for step in lin.steps:
      if step.seqname in whole_seqs or step.fullname in specific:
        toadd.add(step)
    if group.reverse:
      result.add(toadd.reversed())
    else:
      result.add(toadd)

proc listSteps*(lin:Lin, keys:openArray[string]):seq[string] =
  ## List step names that will be run
  return lin.collectSteps(keys).mapIt(it.fullname)

proc helptext*(lin:Lin):string =
  ## Return the block of helptext for the particular context
  result.add """Usage

  lin [variables] [flags] [sequence [sequence...]]
  
  Sequences can be provided in the following ways:
    
    1. Sequence name:   build
    2. Step name:       build/first-step
    3. Range:           build..deploy/last-step

"""
  # Variables
  result.add "Variables"
  for v in lin.variables.values:
    result.add &"\L  --{v.name}"
    case v.kind
    of BooleanVar:
      discard
    of StringVar:
      if v.strVal != "":
        result.add &"[={v.strVal}]"
    result.add &"  {v.help}"
  result.add "\L"
  # Flags
  result.add "\LFlags\L"
  result.add "  -h/--help - Display this help\L"
  result.add "  -l        - List sequences without running\L"
  # Sequences
  result.add "\LSequences\L"
  if lin.sequences.len > 0:
    var biggest_seqname = toSeq(lin.sequences.keys()).mapIt(it.len).max()
    for s in lin.sequences.values:
      let name_padding = " ".repeat(biggest_seqname - s.name.len)
      result.add &"  {s.name}{name_padding} - {s.help}"
      if s.includes.len > 0:
        let space = " ".repeat(biggest_seqname)
        let include_str = s.includes.join(",")
        result.add &"\L  {space}   includes: {include_str}"
      result.add "\L"
  # Usage

#-------------------------
# Variables
#-------------------------
proc normalizeVar(name:string):string =
  result = name.toLowerAscii()
  if result.find(re"[^a-z0-9-]") != -1:
    raise newException(ValueError, &"Invalid variable name: {name}")

proc saveVar(lin:Lin, v:Variable) =
  let name = v.name.normalizeVar()
  if lin.variables.hasKey(name):
    raise newException(DuplicateName, &"Variable {name} already defined")
  lin.variables[name] = v

proc strVar*(lin:Lin, name:string, default = "", help = ""):Variable =
  ## Define a new variable that can be used in build steps
  let name = name.normalizeVar()
  result = Variable(name:name, kind:StringVar, strVal:default, help:help)
  lin.saveVar(result)

proc boolVar*(lin:Lin, name:string, help = ""):Variable =
  ## Define a new boolean flag
  let name = name.normalizeVar()
  result = Variable(name:name, kind:BooleanVar, boolVal:false, help:help)
  lin.saveVar(result)

proc extractVarFlags*(lin:Lin, params:openArray[string]):seq[string] =
  ## Remove --var-flags from a sequence of command-line args
  var i = 0
  while i < params.len:
    let param = params[i]
    if param.startsWith("--"):
      # flag
      let name = param.strip(leading = true, trailing = false, chars = {'-'})
      let parts = name.split('=', 1)
      if parts.len == 2:
        # --key=value
        let
          key = parts[0]
          val = parts[1]
        if lin.variables.hasKey(key):
          lin.variables[key].strVal = val
        else:
          raise newException(UnknownFlag, param)
      else:
        # --key [value]
        if lin.variables.hasKey(name):
          let variable = lin.variables[name]
          case variable.kind
          of StringVar:
            i.inc()
            variable.strVal = params[i]
          of BooleanVar:
            variable.boolVal = true
        else:
          raise newException(UnknownFlag, param)
    else:
      # extra
      result.add(param)
    i.inc()

#-------------------------
# Sequences
#-------------------------
template step*(s:Sequence, nm:string, fun:untyped) =
  s.lin.steps.add(Step(seqname: s.name, name: nm, fn: proc() = fun))

#-------------------------
# Steps
#-------------------------
proc fullname*(s:Step):string {.inline.} = s.seqname & DELIM & s.name

proc stamp(d:Duration):string =
  "(" & $d.inSeconds & "s)"

proc run*(lin:Lin, args:openArray[string]):bool =
  addExitProc(resetAttributes)

  let steps = lin.collectSteps(args)
  let grand_start = getTime()
  result = true

  let orig_parentdir = getEnv("LIN_PARENTDIR", "")
  let orig_parentstep = getEnv("LIN_PARENTSTEP", "")
  
  let step_prefix = if orig_parentstep == "": "" else: orig_parentstep & "/" & getAppDir().relativePath(orig_parentdir) & "/"

  for stepn,step in steps:
    let left = steps.len - stepn
    let fq_stepnumber = step_prefix & $left
    var
      msg:string
      res:RunStatus
      start = getTime()
      step_total: Duration
    stderr.styledWrite(styleDim, "[lin] ")
    stderr.styledWriteLine(styleReverse, &"{fq_stepnumber} {step.fullname}")
    try:
      if getEnv("LIN_PARENTDIR", "") == "":
        # root invocation
        putEnv("LIN_PARENTDIR", getAppDir())
      putEnv("LIN_PARENTSTEP", fq_stepnumber)
      step.fn()
      step_total = getTime() - start
      res = resOk
    except SkipSignal:
      res = resSkip
      msg = getCurrentExceptionMsg()
    except:
      res = resFail
      msg = getCurrentExceptionMsg()
    finally:
      putEnv("LIN_PARENTSTEP", orig_parentstep)
      putEnv("LIN_PARENTDIR", orig_parentdir)
    
    var
      color = fgGreen
      code = "ok"
    case res
    of resOk:
      color = fgGreen
      code = "ok"
    of resFail:
      color = fgRed
      code = "fail"
    of resSkip:
      color = fgCyan
      code = "skipped"

    stderr.styledWrite(styleDim, "[lin] ")
    stderr.styledWrite(color, styleReverse, &"{fq_stepnumber} {step.fullname}")
    stderr.styledWriteLine(color, &" done {code} {step_total.stamp} {msg}")
    if res == resFail:
      result = false
      break
  
  if orig_parentdir == "":
    let grand_total = getTime() - grand_start
    stderr.styledWriteLine(styleDim, &"[lin] all done {grand_total.stamp}")

proc cli*(lin:Lin) =
  setStdIoUnbuffered()
  var params = commandLineParams()
  if "--help" in params or "-h" in params:
    echo lin.helptext()
    quit(0)
  var runmode = "run"
  if "-l" in params:
    params = params.filterIt(it != "-l")
    runmode = "list"
  params = lin.extractVarFlags(params)
  if params.len == 0:
    params = lin.default_seqs
  if params.len == 0:
    echo "No sequences chosen. See --help for more info"
    quit(1)
  if runmode == "list":
    for x in lin.listSteps(params):
      echo x
  else:
    if not lin.run(params):
      quit(1)


#-------------------------
# Utilities for writing linseed files
#-------------------------
type
  SubprocessError* = object of CatchableError
  RunResult = tuple
    cmdstr: string
    rc: int
    stdout: string
    stderr: string

when hasThreads:
  type
    FileHandleReader = tuple
      stream: Stream
      ch: ptr Channel[string]
      isOut: bool
      capture: bool
  proc readFromStream(fh: FileHandleReader) {.thread.} =
    let label = if fh.isOut: "OUT: " else: "ERR: "
    if fh.capture:
      let data = fh.stream.readAll()
      (fh.ch[]).send(data)
    else:
      let passthru = if fh.isOut: stdout else: stderr
      while not fh.stream.atEnd:
        var data: string
        try:
          fh.stream.read(data)
        except:
          break
        try:
          passthru.write(data)
        except:
          discard

proc run*(args:seq[string], captureStdout, captureStderr = false): RunResult =
  let cmdstr = args.join(" ")
  stderr.styledWriteLine(styleDim, "[lin] ", &"# {cmdstr}")
  let cmd = if args[0] == "lin": getEnv("LIN_BIN", args[0]) else: args[0]
  var opts = {poUsePath}
  if captureStdout or captureStderr:
    discard
  else:
    opts.incl poParentStreams
  var p = startProcess(cmd, args = args[1..^1], options = opts)
  var
    outs: string
    errs: string
  if poParentStreams in opts:
    # let it run
    discard p.waitForExit()
  else:
    # pump the output
    when not hasThreads:
      raise ValueError.newException("Must run lin with --threads:on to capture stdout/stderr")
    else:
      var
        tout: Thread[FileHandleReader]
        terr: Thread[FileHandleReader]
        outChan: Channel[string]
        errChan: Channel[string]
      if captureStdout:
        var outstream = p.outputStream()
        outChan.open()
        tout.createThread(readFromStream, (outstream, addr outChan, true, captureStdout))
      if captureStderr:
        var errstream = p.errorStream()
        errChan.open()
        terr.createThread(readFromStream, (errstream, addr errChan, false, captureStderr))
      if captureStdout:
        outs = outChan.recv()
      if captureStderr:
        errs = errChan.recv()
      joinThreads([tout, terr])
      discard p.waitForExit()

  let rc = p.peekExitCode()
  p.close()
  result = (cmdstr, rc, outs, errs)

proc sh*(args:varargs[string]) =
  ## Run a subprocess, failing if it fails
  let ret = run(@args)
  if ret.rc != 0:
    raise newException(SubprocessError, &"Error executing: {ret.cmdstr}")

proc shmaybe*(args:varargs[string]) =
  ## Run a subprocess, ignoring exit code
  discard run(@args)

proc shout*(args: varargs[string]): string =
  ## Run a subprocess, returning stdout as a string
  run(@args, captureStdout = true).stdout

proc sherr*(args: varargs[string]): string =
  ## Run a subprocess, returning stderr as a string
  run(@args, captureStderr = true).stderr

proc shouterr*(args: varargs[string]): tuple[o: string, e: string] =
  ## Run a subprocess, returning stdout + stderr as a string
  let res = run(@args, captureStdout = true, captureStderr = true)
  (res.stdout, res.stderr)

template cd*(newdir:string, body:untyped):untyped =
  ## Do some code within a new directory
  let
    olddir = getCurrentDir().absolutePath
    newabs = newdir.absolutePath
  try:
    if newabs != olddir:
      stderr.styledWriteLine(styleDim, "[lin] ", "# cd " & newabs.relativePath(olddir))
      setCurrentDir(newabs)
    body
  finally:
    if newabs != olddir:
      stderr.styledWriteLine(styleDim, "[lin] ", "# cd " & olddir.relativePath(newabs))
      setCurrentDir(olddir)

proc skip*(reason = "") =
  raise newException(SkipSignal, reason)

proc newerSources*(output:openArray[string], sources: openArray[string]): seq[string] =
  ## Returns the set of sources files that are newer than the oldest
  ## output file.  If anything is returned, a rebuild should happen.
  ## 
  ## .. code-block:: nim
  ##   import lin, os
  ## 
  ##   let
  ##     src = @["prog.nim", "prog2.nim"]
  ##     dst = @["prog.out", "prog_stats.txt"]
  ##   if dst.newerSources(src).len > 0:
  ##      echo "Refreshing ..."
  ##      # do something to generate the outputs
  ##   else:
  ##      echo "All done!"
  assert len(sources) > 0, "Must include some source files"
  var minTargetTime = low(Time)
  for target in output:
    try:
      let targetTime = getLastModificationTime(target)
      if minTargetTime == low(Time):
        minTargetTime = targetTime
      elif targetTime < minTargetTime:
        minTargetTime = targetTime
    except OSError:
      # There is a missing output file, so every source is newer
      return toSeq(sources)

  for s in sources:
    try:
      let srcTime = getLastModificationTime(s)
      if srcTime > minTargetTime:
        result.add(s)
    except OSError:
      raise newException(CatchableError, "Error accessing source file: " & s)

proc hasNewerSources*(output: openArray[string], sources: openArray[string]): bool =
  ## Returns true if a rebuild should happen because source files have
  ## been updated.
  return output.newerSources(sources).len > 0

proc olderThan*(output:openArray[string], input:openArray[string]):bool {.deprecated: "Use newerSources or hasNewerSources instead".}=
  ## Returns true if any ``src`` is newer than the oldest ``targets``.
  ##
  ## .. code-block:: nim
  ##   import lin, os
  ##
  ##   let
  ##     src = @["prog.nim", "prog2.nim"]
  ##     dst = @["prog.out", "prog_stats.txt"]
  ##   if dst.olderThan(src):
  ##      echo "Refreshing ..."
  ##      # do something to generate the outputs
  ##   else:
  ##      echo "All done!"
  assert len(input) > 0, "Must include some source files"
  var minTargetTime = low(Time)
  for target in output:
    try:
      let targetTime = getLastModificationTime(target)
      if minTargetTime == low(Time):
        minTargetTime = targetTime
      elif targetTime < minTargetTime:
        minTargetTime = targetTime
    except OSError:
      return true

  for s in input:
    try:
      let srcTime = getLastModificationTime(s)
      if srcTime > minTargetTime:
        return true
    except OSError:
      raise newException(CatchableError, "Error accessing file: " & s)

proc olderThan*(output:string, input:openArray[string]):bool {.inline.} = olderThan([output], input)
proc olderThan*(output:openArray[string], input:string):bool {.inline.} = olderThan(output, [input])
proc olderThan*(output:string, input:string):bool {.inline.} = olderThan([output], [input])

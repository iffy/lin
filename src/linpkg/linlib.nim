import algorithm
import os
export os
import osproc
import re
import sequtils
import strformat
import strutils
import tables
import terminal
export terminal
import times

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
    sequences: TableRef[string, Sequence]
    steps: seq[Step]
    variables: TableRef[string, Variable]
    default_seqs: seq[string]
  
  RunStatus = enum
    resOk,
    resFail,
    resSkip,

const DELIM = ":"

proc fullname*(s:Step):string {.inline.}

proc newLin*():Lin =
  ## Make a new Lin. Typically, you should just use
  ## the singleton built-in to the library. This is mostly
  ## here for testing.
  result = Lin()
  result.variables = newTable[string, Variable]()
  result.sequences = newTable[string, Sequence]()

proc sequence*(lin:Lin, name:string, help = "", reverse = false, includes:seq[string] = @[], default = false):Sequence =
  result = Sequence(name: name, lin: lin, help:help, reverse:reverse, includes:includes)
  lin.sequences[name] = result
  if default:
    lin.default_seqs.add(name)

proc allIncludes(lin:Lin, key:string):seq[string] =
  ## Return all the includes (recursively) for a sequence name
  var s = lin.sequences[key]
  for x in s.includes:
    result.add(lin.allIncludes(x))
  result.add(s.includes)

proc seqname*(x:string):string {.inline.} = x.split(DELIM, 1)[0]

proc collectSteps*(lin:Lin, keys:openArray[string]):seq[Step] =
  ## List the steps that will be run
  # First group them by direction
  var
    groups:seq[tuple[reverse:bool, keys:seq[string]]]
  groups.add((reverse:false, keys: @[]))
  for key in keys:
    let seqname = key.seqname
    if not lin.sequences.hasKey(seqname):
      raise newException(KeyError, &"No such sequence: {key}")
    let s = lin.sequences[seqname]
    if s.reverse != groups[^1].reverse:
      # new direction
      groups.add((reverse:s.reverse, keys: @[]))
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
  for s in lin.sequences.values:
    result.add &"  {s.name}  {s.help}"
    if s.includes.len > 0:
      let space = " ".repeat(s.name.len)
      let include_str = s.includes.join(",")
      result.add &"\L  {space}  includes: {include_str}"
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
  system.addQuitProc(resetAttributes)

  let steps = lin.collectSteps(args)
  let grand_start = getTime()
  result = true

  for stepn,step in steps:
    let left = steps.len - stepn
    var
      msg:string
      res:RunStatus
      start = getTime()
      step_total: Duration
    stderr.styledWriteLine("[lin] ", styleReverse, &"{left} {step.fullname}")
    try:
      step.fn()
      step_total = getTime() - start
      res = resOk
    except SkipSignal:
      res = resSkip
      msg = getCurrentExceptionMsg()
    except:
      res = resFail
      msg = getCurrentExceptionMsg()
    
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

    stderr.styledWrite("[lin] ", color, styleReverse, &"{left} {step.fullname}")
    stderr.styledWriteLine(color, &" done {code} {step_total.stamp} {msg}")
    if res == resFail:
      result = false
      break
  
  let grand_total = getTime() - grand_start
  stderr.writeLine(&"[lin] all done {grand_total.stamp}")

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

proc run*(args:seq[string]):RunResult =
  let cmdstr = args.join(" ")
  stderr.styledWriteLine("[lin] ", styleDim, &"# {cmdstr}")
  var p = startProcess(args[0], args = args[1..^1], options = {poParentStreams, poUsePath})
  let rc = p.waitForExit()
  p.close()
  result = (cmdstr, rc)

proc sh*(args:varargs[string]) =
  ## Run a subprocess, failing if it fails
  let ret = run(@args)
  if ret.rc != 0:
    raise newException(SubprocessError, &"Error executing: {ret.cmdstr}")

proc shmaybe*(args:varargs[string]) =
  ## Run a subprocess, ignoring exit code
  discard run(@args)

template cd*(newdir:string, body:untyped):untyped =
  ## Do some code within a new directory
  let
    olddir = getCurrentDir().absolutePath
    newabs = newdir.absolutePath
  try:
    if newabs != olddir:
      stderr.styledWriteLine("[lin] ", styleDim, "# cd " & newabs.relativePath(olddir))
      setCurrentDir(newabs)
    body
  finally:
    if newabs != olddir:
      stderr.styledWriteLine("[lin] ", styleDim, "# cd " & olddir.relativePath(newabs))
      setCurrentDir(olddir)

proc skip*(reason = "") =
  raise newException(SkipSignal, reason)

proc olderThan*(output:openArray[string], input:openArray[string]):bool =
  ## Returns true if any ``src`` is newer than the oldest ``targets``.
  ##
  ## .. code-block:: nim
  ##   import nake, os
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
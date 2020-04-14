import os
import osproc
import times
import terminal
export terminal
import strutils
import strformat
import tables
import streams

type
  UnknownFlag* = object of CatchableError
  Sequence* = ref object
    lin: Lin
    name: string
    help: string
  
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
    sequences: seq[Sequence]
    steps: seq[Step]
    variables: TableRef[string, Variable]
  
  RunStatus = enum
    resOk,
    resFail,
    resSkip,

const DELIM = ":"

proc newLin*():Lin =
  ## Make a new Lin. Typically, you should just use
  ## the singleton built-in to the library. This is mostly
  ## here for testing.
  result = Lin()
  result.variables = newTable[string, Variable]()

proc sequence*(lin:Lin, name:string, help = ""):Sequence =
  result = Sequence(name: name, lin: lin, help:help)
  lin.sequences.add(result)

proc collectSteps*(lin:Lin, keys:openArray[string]):seq[Step] =
  ## List the steps that will be run
  var
    whole_seqs:seq[string]
    specific:seq[string]
  for key in keys:
    if key.find(DELIM) == -1:
      whole_seqs.add(key)
    elsE:
      specific.add(key)

  for step in lin.steps:
    if step.seqname in whole_seqs:
      result.add(step)

proc helptext*(lin:Lin):string =
  ## Return the block of helptext for the particular context
  # Variables
  result.add "Variables\L"
  for v in lin.variables.values:
    result.add &"  --{v.name}"
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
  for s in lin.sequences:
    result.add &"  {s.name}  {s.help}\L"
  # Usage

#-------------------------
# Variables
#-------------------------
proc strVar*(lin:Lin, name:string, default = "", help = ""):Variable =
  ## Define a new variable that can be used in build steps
  result = Variable(name:name, kind:StringVar, strVal:default, help:help)
  lin.variables[name] = result

proc boolVar*(lin:Lin, name:string, help = ""):Variable =
  ## Define a new boolean flag
  result = Variable(name:name, kind:BooleanVar, boolVal:false, help:help)
  lin.variables[name] = result

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
proc step*(s:Sequence, name:string, fn:proc()) =
  ## Add a step to the given sequence
  s.lin.steps.add(Step(seqname: s.name, name: name, fn: fn))

#-------------------------
# Steps
#-------------------------
proc fullname*(s:Step):string {.inline.} = s.seqname & DELIM & s.name

proc stamp(d:Duration):string =
  "(" & $d.inMilliseconds & "ms)"

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
  var params = commandLineParams()
  if "--help" in params:
    echo lin.helptext()
    quit(0)
  params = lin.extractVarFlags(params)
  if not lin.run(params):
    quit(1)


#-------------------------
# Utilities
#-------------------------
type
  SubprocessError* = object of CatchableError
  RunResult = tuple
    cmdstr: string
    outp: string
    errp: string
    rc: int

proc run*(args:seq[string]):RunResult =
  let cmdstr = args.join(" ")
  stderr.styledWriteLine("[lin] ", styleDim, &"# {cmdstr}")
  var p = startProcess(args[0], args = args[1..^1], options = {poUsePath})
  var
    outp:string
    errp:string
    oh = p.outputStream()
    eh = p.errorStream()

  while not oh.atEnd() or not eh.atEnd():
    while not oh.atEnd():
      let line = oh.readLine() & "\L"
      # echo "stdout line: ", line.repr
      stdout.write(line)
      outp.add(line)
    while not eh.atEnd():
      let line = eh.readLine() & "\L"
      # echo "stderr line: ", line.repr
      stderr.write(line)
      errp.add(line)

  # let rc = p.waitForExit()
  p.close()
  let rc = p.peekExitCode()
  result = (cmdstr, outp, errp, rc)

proc sh*(args:varargs[string]) =
  ## Run a subprocess, failing if it fails
  let ret = run(@args)
  if ret.rc != 0:
    raise newException(SubprocessError, &"Error executing: {ret.cmdstr}")

proc shmaybe*(args:varargs[string]) =
  ## Run a subprocess, ignoring exit code
  discard run(@args)

proc shout*(args:varargs[string]):string =
  ## Run a subprocess, capturing output
  let ret = run(@args)
  result = ret.outp
  if ret.rc != 0:
    raise newException(SubprocessError, &"Error executing: {ret.cmdstr}")

proc shmout*(args:varargs[string]):string =
  ## Run a subprocess, capturing output, ignoring exit code
  let ret = run(@args)
  result = ret.outp & ret.errp

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
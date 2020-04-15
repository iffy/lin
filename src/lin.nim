import linpkg/linlib
export linlib
import linpkg/singleton
export singleton

when isMainModule:
  import os
  import osproc
  var
    dirname = getCurrentDir()
    path: string
  while true:
    path = dirname / "linseed.nim"
    if path.existsFile():
      break
    else:
      if dirname == "":
        echo "Could not find linseed.nim"
        quit(1)
      dirname = dirname.parentDir()
  let params = commandLineParams()
  var args = @[
    "c",
    "-r",
    "--debuginfo:off",
    "--hints:off",
    "--verbosity:0",
    path,
  ]
  args.add(params)
  let p = startProcess("nim", args = args,
    options = {poParentStreams, poUsePath})
  let rc = p.waitForExit()
  p.close()
  quit(rc)


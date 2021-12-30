import linpkg/linlib
export linlib
import linpkg/singleton
export singleton

when isMainModule:
  import os
  import osproc
  putEnv("LIN_BIN", getAppFilename())
  var
    dirname = getCurrentDir()
    path: string
  while true:
    path = dirname / "linseed.nim"
    if path.fileExists():
      break
    else:
      if dirname == "":
        echo "Could not find linseed.nim"
        quit(1)
      dirname = dirname.parentDir()
  setCurrentDir(dirname)
  let params = commandLineParams()
  var args = @[
    "c",
    "-d:lin",
    "-r",
    "--debuginfo:off",
    "--hints:off",
    "--verbosity:0",
    "linseed.nim",
  ]
  args.add(params)
  let p = startProcess("nim", args = args,
    options = {poParentStreams, poUsePath})
  let rc = p.waitForExit()
  p.close()
  quit(rc)


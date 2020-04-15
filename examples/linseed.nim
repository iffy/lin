import os
import lin

var build = sequence("build", default = true)
var clean = sequence("clean", reverse = true)

let debug = boolVar("debug")
let name = strVar("name", default = "bob")

build.step "first":
  try:
    createDir("lintest_tmp")
    cd "lintest_tmp":
      sh "ls", "-al"
  finally:
    removeDir("lintest_tmp")

clean.step "first":
  discard

clean.step "second":
  discard

build.step "second":
  echo "hello, ", name.strVal
  if debug.boolVal:
    echo "DEBUG OUTPUT"
  sleep(20)

if isMainModule:
  cli()

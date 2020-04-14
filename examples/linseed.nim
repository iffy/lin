import os
import lin

var build = sequence("build")
var clean = sequence("clean")

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
  discard

if isMainModule:
  cli()

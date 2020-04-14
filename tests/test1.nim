import unittest
import lin
import os
import strutils

const tmpdir = "somefake_lindir"
template withtmp(body:untyped):untyped =
  try:
    createDir(tmpdir)
    body
  finally:
    removeDir(tmpdir)

test "basic run":
  var o:seq[string]
  var i = newLin()
  var build = i.sequence("build")
  check "build" in i.helptext()

  build.step "1":
    o.add("1")
  check i.run(["build"])
  assert o.len == 1
  assert o[0] == "1"

test "sequence help":
  var i = newLin()
  var build = i.sequence("build", help="Something")
  check "Something" in i.helptext()

test "variable default":
  var o:seq[string]
  var i = newLin()
  var build = i.sequence("build")
  let foo = i.strVar("foo", default = "aaa")
  check "foo" in i.helptext()
  check "aaa" in i.helptext()
  echo i.helptext()

  build.step "1":
    o.add(foo.strVal)
  check i.run(["build"])
  check o[0] == "aaa"

  o.setLen(0)
  foo.strVal = "bar"
  check i.run(["build"])
  check o[0] == "bar"

test "variable help":
  var o:seq[string]
  var i = newLin()
  var build = i.sequence("build")
  let foo = i.strVar("foo", help="bbb")
  check "bbb" in i.helptext()

test "command line variables":
  var i = newLin()
  let foo = i.strVar("foo")
  let leftover = i.extractVarFlags(["--foo", "hi", "extra"])
  check leftover == @["extra"]
  check foo.strVal == "hi"

test "unknown vars":
  var i = newLin()
  expect Exception:
    discard i.extractVarFlags(["--foo", "hi", "extra"])

test "bool vars":
  var i = newLin()
  let foo = i.boolVar("foo")
  check foo.boolVal == false
  let leftover = i.extractVarFlags(["--foo", "hi", "extra"])
  check leftover == @["hi", "extra"]
  check foo.boolVal == true

test "sh":
  sh "echo", "foo"

test "sh fail":
  expect Exception:
    sh "false"

test "shmaybe":
  shmaybe "true"
  shmaybe "false"

test "shout":
  let o = shout("echo", "foo")
  check o == "foo\n"
  expect Exception:
    discard shout "false"

test "shmout":
  let o = shmout("false")
  check o == ""
  check "hey\L" == shmout("echo", "hey")

test "cd":
  withtmp:
    let expected = tmpdir.absolutePath
    cd tmpdir:
      check getCurrentDir().absolutePath == expected

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
  discard i.sequence("build", help="Something")
  check "Something" in i.helptext()

test "list steps":
  var i = newLin()
  var a = i.sequence("a")
  var b = i.sequence("b")
  a.step "1": discard
  b.step "2": discard
  a.step "3": discard
  check i.listSteps(["a"]) == @["a:1", "a:3"]
  check i.listSteps(["b"]) == @["b:2"]
  check i.listSteps(["a", "b"]) == @["a:1", "b:2", "a:3"]
  check i.listSteps(["b", "a", "a"]) == @["a:1", "b:2", "a:3"]

test "reverse":
  var i = newLin()
  var a = i.sequence("a")
  var b = i.sequence("b", reverse=true)
  a.step "1": discard
  b.step "2": discard
  b.step "3": discard
  a.step "4": discard

  check i.listSteps(["b"]) == @["b:3", "b:2"]
  check i.listSteps(["a", "b"]) == @["a:1", "a:4", "b:3", "b:2"]
  check i.listSteps(["b", "a"]) == @["b:3", "b:2", "a:1", "a:4"]

test "includes":
  var i = newLin()
  var a = i.sequence("a")
  var b = i.sequence("b", includes = @["a"])
  a.step "1": discard
  b.step "2": discard
  a.step "3": discard

  check i.listSteps(["a"]) == @["a:1", "a:3"]
  check i.listSteps(["b"]) == @["a:1", "b:2", "a:3"]
  check i.listSteps(["a", "b"]) == @["a:1", "b:2", "a:3"]
  check i.listSteps(["b", "a"]) == @["a:1", "b:2", "a:3"]

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

test "variable dupe":
  var i = newLin()
  discard i.strVar("first")
  expect Exception:
    discard i.strVar("first")
  expect Exception:
    discard i.strVar("fIRST")

test "variable allowed chars":
  var i = newLin()
  let not_allowed = @[
    "foo_bar",
    "foo.bar",
    "foo/bar",
    "foo=bar",
    "foo+bar",
    "foo bar",
    "foo\tbar",
  ]
  for x in not_allowed:
    expect Exception:
      discard i.strVar(x)
    expect Exception:
      discard i.boolVar(x)

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

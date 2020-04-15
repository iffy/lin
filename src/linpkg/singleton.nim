import ./linlib
export linlib

let singleton = newLin()

proc cli*() =
  singleton.cli()

template sequence*(args: varargs[untyped]):untyped =
  singleton.sequence(args)

template strVar*(args: varargs[untyped]):untyped =
  singleton.strVar(args)

template boolVar*(args: varargs[untyped]):untyped =
  singleton.boolVar(args)


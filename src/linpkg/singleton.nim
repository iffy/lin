import ./linlib
export linlib

let singleton = newLin()

proc cli*() =
  singleton.cli()

proc sequence*(name:string, help = ""):Sequence =
  singleton.sequence(name, help)

proc strVar*(name:string, default = "", help = ""):Variable =
  singleton.strVar(name, default, help)

proc boolVar*(name: string, help = ""):Variable =
  singleton.boolVar(name, help)

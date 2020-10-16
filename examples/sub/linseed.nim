import lin

var build = sequence("build")

build.step "hello":
  echo "hello"

if isMainModule:
  cli()

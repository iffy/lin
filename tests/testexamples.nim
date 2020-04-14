import unittest
import os
import lin

test "only":
  cd getAppDir()/"..":
    sh "nimble", "build", "lin"
  cd getAppDir()/".."/"examples":
    sh "ls", "-al"
    sh "../lin", "clean"
    sh "../lin", "build"

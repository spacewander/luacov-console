package = "luacov-console"
version = "scm-0"
source = {
    url = "git://github.com/spacewander/luacov-console",
    branch = "master",
}
description = {
    summary = "Combine luacov with your development cycle and CI",
    detailed = "Combine luacov with your development cycle and CI",
    homepage = "https://github.com/spacewander/luacov-console",
    license = "MIT"
}
dependencies = {
    "lua >= 5.1",
    "luacov > 0.5",
    "luafilesystem",
    "argparse",
}
build = {
   type = "builtin",
   -- I hope it's simple enough to use without any docs
   copy_directories = {},
   modules = {
      ['luacov.reporter.console'] = "src/luacov/reporter/console.lua",
   },
   install = {
      bin = {
         ["luacov-console"] = "src/luacov-console.lua",
      }
   },
}

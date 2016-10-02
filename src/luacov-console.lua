#!/usr/bin/env lua

local luacov = require("luacov.runner")
local reporter = require("luacov.reporter.console")
local argparse = require("argparse")

local function index()
    local configuration = luacov.load_config()
    local idx_file = configuration.reportfile .. '.index'
end

local function print_results(pattern, no_colored)
end

local function print_summary(no_colored)
end

local parser = argparse("luacov-console",
                        "Combine luacov with your development cycle and CI")
parser:argument("workdir", "Specific the source directory", '.')
parser:option("--no-colored", "Don't print with color."):args(0)
parser:option("-l --list", "List coverage results of files matched given lua pattern(s)."):args('+')
parser:option("-s --summary", "Show coverage summary."):args(0)

local args = parser:parse()

if args.list then
    print_results(args.list, args.no_colored)
elseif args.summary then
    print_summary(args.no_colored)
else
    reporter.report(args)
end

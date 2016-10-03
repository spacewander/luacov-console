#!/usr/bin/env lua

local luacov = require("luacov.runner")
local configuration = luacov.load_config()
local reporter = require("luacov.reporter.console")
local argparse = require("argparse")

local function print_error(...)
    io.stderr:write(...)
    os.exit(1)
end

local function index()
    local idx_file = configuration.reportfile .. '.index'
    local idx = {
        filenames = {}
    }
    for line in io.lines(idx_file) do
        local filename, start, stop = line:match("(.+):(%d+) (%d+)$")
        if not filename then
            -- Index file is corrupted
            break
        end
        if line:sub(1, 7) ~= 'Summary' then
            idx.filenames[filename] = {
                start = tonumber(start),
                stop = tonumber(stop),
            }
        else
            idx.summary = {
                start = tonumber(start),
                stop = tonumber(stop),
            }
        end
    end
    return idx
end

local function print_results(patterns, no_colored)
    local data_file = configuration.reportfile
    local file, err = io.open(data_file)
    if not file then
        print_error("Can't open ", data_file, ": ", err)
    end

    for filename, block in pairs(index().filenames) do
        for _, pattern in ipairs(patterns) do
            if filename:match(pattern) then
                file:seek("set", block.start)
                if no_colored then
                    --print(text)
                else
                    for line in file:lines() do
                        if file:seek() <= block.stop then
                            print(line)
                        end
                    end
                end

                -- Let's go to the next file
                break
            end
        end
    end

    file:close()
end

local function print_summary(no_colored)
    local data_file = configuration.reportfile
    local file, err = io.open(data_file)
    if not file then
        print_error("Can't open ", data_file, ": ", err)
    end

    local block = index().summary
    file:seek("set", block.start)
    if no_colored then
        --print(summary)
    else
        for line in file:lines() do
            if file:seek() <= block.stop then
                print(line)
            end
        end
    end

    file:close()
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

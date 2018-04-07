#!/usr/bin/env lua

local luacov = require("luacov.runner")
local configuration = luacov.load_config()
local reporter = require("luacov.reporter.console")
local argparse = require("argparse")
local lfs = require('lfs')

local VERSION = "1.1.0"

-- Use ANSI escape sequences.
-- https://en.wikipedia.org/wiki/ANSI_escape_code
-- The Win32 console did not support ANSI escape sequences at all until Windows 10.
-- FIXME If anyone knows how to color text in Win32 console before Win10,
-- don't hesitate to send me a pull request!
local function colored_print(color, text)
    local end_color = "\27[0m"
    local colors = {
        black = "\27[30;1m",
        red = "\27[31;1m",
        green = "\27[32;1m",
        yellow = "\27[33;1m",
        white = "\27[37;1m",
    }

    local start_color = colors[color] or ""
    print(start_color .. text .. end_color)
end

local function print_error(...)
    io.stderr:write(...)
    os.exit(1)
end

local function index()
    local report_file = configuration.reportfile
    local idx_file = report_file .. '.index'
    local idx_file_ctime, err = lfs.attributes(idx_file, "change")
    if not idx_file_ctime then
        print_error("Can't stat ctime of ", idx_file, ": ", err)
    end
    local report_file_ctime, err = lfs.attributes(report_file, "change")
    if not report_file_ctime then
        print_error("Can't stat ctime of ", report_file_ctime, ": ", err)
    end
    if report_file_ctime > idx_file_ctime then
        print_error(report_file, " was changed after ", idx_file, " created."..
            " Please rerun luacov-console <dir> to recreate the index.")
    end

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

    local output = no_colored and print or function(line)
        if line:sub(1, 1) == '0' then
            colored_print('red', line:sub(3))
        else
            -- Treat not counted line as coveraged
            colored_print('green', line:sub(3))
        end
    end
    for filename, block in pairs(index().filenames) do
        for _, pattern in ipairs(patterns) do
            if filename:match(pattern) then
                file:seek("set", block.start)
                for line in file:lines() do
                    if file:seek() <= block.stop then
                        output(line)
                    else
                        break
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

    local output = no_colored and print or function(line)
        local coverage_str = line:sub(-6, -2)
        local coverage = coverage_str == '00.00' and 100 or tonumber(coverage_str)
        local colors = {
            'red',
            'yellow',
            'white',
            'green',
        }
        local levels = {
            30,
            60,
            80,
            100,
        }
        for i, level in ipairs(levels) do
            if coverage <= level then
                colored_print(colors[i], line)
                return
            end
        end
        -- Should not reach here
        -- So if we see black color output, it must be something wrong
        colored_print('black', line)
    end

    local in_stats = false
    for line in file:lines() do
        if file:seek() <= block.stop then
            if line:sub(1, 10) == ('-'):rep(10) then
                in_stats = not in_stats
                print(line)
            elseif in_stats or line:sub(1, 5) == 'Total' then
                output(line)
            else
                print(line)
            end
        else
            break
        end
    end

    file:close()
end

local parser = argparse("luacov-console",
                        "Combine luacov with your development cycle and CI")
parser:argument("workdir", "Specific the source directory", '.')
parser:option("--version", "Print version"):args(0)
parser:option("--no-colored", "Don't print with color."):args(0)
parser:option("-l --list", "List coverage results of files matched given lua pattern(s)."):args('+')
parser:option("-s --summary", "Show coverage summary."):args(0)

local args = parser:parse()

if args.list then
    print_results(args.list, args.no_colored)
elseif args.summary then
    print_summary(args.no_colored)
elseif args.version then
    print(VERSION)
else
    reporter.report(args)
end

local lfs = require('lfs')
local luacov = require("luacov.runner")
local luacov_reporter = require("luacov.reporter")

local ReporterBase = luacov_reporter.ReporterBase
local ConsoleReporter = setmetatable({}, ReporterBase) do
ConsoleReporter.__index = ConsoleReporter

local function match_any(patterns, str, on_empty)
    if not patterns or not patterns[1] then
        return on_empty
    end

    for _, pattern in ipairs(patterns) do
        if string.match(str, pattern) then
            return true
        end
    end

    return false
end

local function is_dir(path)
    return lfs.attributes(path, "mode") == "directory"
end

local function is_regular_file(path)
    return lfs.attributes(path, "mode") == "file"
end

local function dirwalk(pattern, filter_fn)
    if not is_dir(pattern) then
        return is_regular_file(pattern) and { pattern } or {}
    end

    local sep = package.config:sub(1,1)
    local dir_stack = { pattern }
    local files = {}

    while #dir_stack > 0 do
        local dir = dir_stack[#dir_stack]
        table.remove(dir_stack)
        local ok, dir_walker, dir_obj = pcall(lfs.dir, dir)
        while ok do
            local path = dir_walker(dir_obj)
            if not path then break end
            if path ~= '.' and path ~= '..' and
                    filter_fn(dir .. sep .. path) then
                path = dir .. sep .. path
                if is_regular_file(path) then
                    files[#files + 1] = path
                elseif is_dir(path) then
                    dir_stack[#dir_stack + 1] = path
                end
            end
        end
    end

    return files
end

function ConsoleReporter:new(config)
    local reporter, err = ReporterBase.new(self, config)
    if not reporter then
        return nil, err
    end

    local has_dot_prefix = false
    for line in io.lines(config.statsfile) do
        local match = string.match(line, "^%d+:%.[/\\]")
        if match then
            has_dot_prefix = true
            break
        end
    end

    local filter = function(filename)
        if is_regular_file(filename) and
                not string.match(filename, "%.lua$") then
            return false
        end

        -- Take and modify from luacov.runner.file_included
        -- Normalize file names before using patterns.
        filename = string.gsub(filename, "%.lua$", "")
        filename = string.gsub(filename, "\\", "/")

        -- If include list is empty, everything is included by default.
        -- If exclude list is empty, nothing is excluded by default.
        return match_any(config.include, filename, true) and
            not match_any(config.exclude, filename, false)
    end

    local workdir = ConsoleReporter.args.workdir
    local sep = package.config:sub(1,1)
    -- Remove path separator
    if workdir:sub(-1) == sep then
        workdir = workdir:sub(1, -2)
    end
    if not is_dir(workdir) then
        return nil, workdir .. " is not a directory"
    end
    reporter._files = {}
    local files = dirwalk(workdir, filter)
    for _, file in ipairs(files) do
        file = luacov.real_name(file)

        if not has_dot_prefix and file:sub(1, 2) == "./" then
            -- luacov uses 'x.lua' instead of './x.lua'
            file = file:sub(3)
        end

        reporter._files[#reporter._files + 1] = file
        if not reporter._data[file] then
            reporter._data[file] = {max = 0, max_hits = 0}
        end
    end

    return reporter, ""
end

function ConsoleReporter:on_start()
    self._summary      = {}
    self._empty_format = " "
    self._zero_format  = "0"
    self._count_format = "*"

    self._filenames = {}
    self._files_start_offset = {}
    self._files_stop_offset = {}
end

function ConsoleReporter:record_offset_start(filename)
    local offset = self._out:seek()
    self._files_start_offset[filename] = offset
end

function ConsoleReporter:record_offset_stop(filename)
    local offset = self._out:seek()
    self._files_stop_offset[filename] = offset
end

function ConsoleReporter:on_new_file(filename)
    self:record_offset_start(filename)
    self._filenames[#self._filenames + 1] = filename
    self:write(("="):rep(78), "\n")
    self:write(filename, "\n")
    self:write(("="):rep(78), "\n")
end

function ConsoleReporter:on_file_error(filename, error_type, message) --luacheck: no self
    io.stderr:write(("Couldn't %s %s: %s\n"):format(error_type, filename, message))
end

function ConsoleReporter:on_empty_line(_, _, line)
    if line == "" then
        self:write("\n")
    else
        self:write(self._empty_format, " ", line, "\n")
    end
end

function ConsoleReporter:on_mis_line(_, _, line)
    self:write(self._zero_format, " ", line, "\n")
end

function ConsoleReporter:on_hit_line(_, _, line, hits)
    self:write(self._count_format:format(hits), " ", line, "\n")
end

function ConsoleReporter:on_end_file(filename, hits, miss)
    self._summary[filename] = { hits = hits, miss = miss }
    self:write("\n")
    self:record_offset_stop(filename)
end

local function calculate_coverage(hits, missed)
    local total = hits + missed

    if total == 0 then
        total = 1
    end

    return hits / total * 100.0
end

function ConsoleReporter:on_end()
    self:record_offset_start('Summary')
    self._filenames[#self._filenames + 1] = 'Summary'
    self:write(("="):rep(78), "\n")
    self:write("Summary\n")
    self:write(("="):rep(78), "\n")
    self:write("\n")

    local lines = {{"File", "Hits", "Missed", "Coverage"}}
    local total_hits, total_missed = 0, 0

    local file_stats = {}
    for _, filename in ipairs(self:files()) do
        local summary = self._summary[filename]

        if summary then
            local hits, missed = summary.hits, summary.miss

            file_stats[#file_stats + 1] = {
                filename,
                summary.hits,
                summary.miss,
                calculate_coverage(hits, missed)
            }

            total_hits = total_hits + hits
            total_missed = total_missed + missed
        end
    end

    -- Order by coverage, miss, filename asc
    table.sort(file_stats, function(a, b)
        if a[4] ~= b[4] then
            return a[4] < b[4]
        elseif a[3] ~= b[3] then
            return a[3] < b[3]
        else
            return a[1] < b[1]
        end
    end)
    for _, file_stat in ipairs(file_stats) do
        file_stat[2] = tostring(file_stat[2])
        file_stat[3] = tostring(file_stat[3])
        file_stat[4] = ("%.2f%%"):format(file_stat[4])
        lines[#lines + 1] = file_stat
    end

    table.insert(lines, {
        "Total",
        tostring(total_hits),
        tostring(total_missed),
        ('%.2f%%'):format(calculate_coverage(total_hits, total_missed))
    })

    local max_column_lengths = {}

    for _, line in ipairs(lines) do
        for column_nr, column in ipairs(line) do
            max_column_lengths[column_nr] = math.max(max_column_lengths[column_nr] or -1, #column)
        end
    end

    local table_width = #max_column_lengths - 1

    for _, column_length in ipairs(max_column_lengths) do
        table_width = table_width + column_length
    end


    for line_nr, line in ipairs(lines) do
        if line_nr == #lines or line_nr == 2 then
            self:write(("-"):rep(table_width), "\n")
        end

        for column_nr, column in ipairs(line) do
            self:write(column)

            if column_nr == #line then
                self:write("\n")
            else
                self:write((" "):rep(max_column_lengths[column_nr] - #column + 1))
            end
        end
    end

    self:record_offset_stop('Summary')
    local idx_file = self._cfg.reportfile .. '.index'
    local idx, err = io.open(idx_file, 'w')
    if not idx then
        io.stderr:write("Can't open ", idx_file, ": ", err)
        os.exit(1)
    end
    for i = 1, #self._filenames do
        local filename = self._filenames[i]
        idx:write(("%s:%d %d\n"):format(
            filename,
            self._files_start_offset[filename],
            self._files_stop_offset[filename]
        ))
    end
end

end

local console = {}
function console.report(args)
    ConsoleReporter.args = args
    return luacov_reporter.report(ConsoleReporter)
end

return console

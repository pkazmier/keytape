#!/usr/bin/env nvim -l

-- ============================================================================
-- Configuration
-- ============================================================================

local Config = {
  -- How long and how much to show onscreen
  inactivity_timer_ms = 1000,
  max_keys_onscreen = 10,

  -- Styling options for subtitles
  font = "JetBrainsMonoNL NFM",
  font_size = 32,
  highlight_color = "&H66CCFF&",
  background_opacity = 0.5,
  key_normalization = "vim_normalization", -- or "icon_normalization"

  -- Positioning of subtitles
  margin_left = 40,
  margin_right = 40,
  margin_vertical = 40,

  -- Template for ASS header with placeholders
  ass_header = [[
[Script Info]
ScriptType: v4.00+
PlayResX: {{res_x}}
PlayResY: {{res_y}}
ScaledBorderAndShadow: yes

[V4+ Styles]
Format: Name, Fontname, Fontsize, PrimaryColour, SecondaryColour, OutlineColour, BackColour, Bold, Italic, Underline, StrikeOut, ScaleX, ScaleY, Spacing, Angle, BorderStyle, Outline, Shadow, Alignment, MarginL, MarginR, MarginV, Encoding
Style: Keys,{{font}},{{font_size}},&H00FFFFFF,&H000000FF,&H00000000,&H00000000,1,0,0,0,100,100,0,0,3,0,0,3,{{margin_left}},{{margin_right}},{{margin_vertical}},1

[Events]
Format: Layer, Start, End, Style, Name, MarginL, MarginR, MarginV, Effect, Text]],
}

local H = {}

-- ============================================================================
-- Main
-- ============================================================================

local main = function()
  -- 1. Parse options from CLI and env vars
  local env_opts = H.parse_env()
  local keylog_file, video_file, cli_opts = H.parse_cli()
  local opts = vim.tbl_extend("force", Config, env_opts, cli_opts)

  local ass_file = video_file:gsub("%.%w+$", "") .. ".ass"
  local out_video = video_file:gsub("%.%w+$", "") .. "-captioned.mp4"

  -- 2. Read the keylog JSON data from VHS
  local keylog_data = table.concat(vim.fn.readfile(keylog_file), "\n")
  local events = vim.json.decode(keylog_data)

  -- 3. Validate and normalize keys
  H.validate_events(events)
  local normalize = assert(H[opts.key_normalization], "invalid normalization function")
  events = vim.tbl_map(function(e)
    e.key = normalize(e.key)
    return e
  end, events)

  -- 4. Generate an ASS file with the subtitles
  opts.res_x, opts.res_y = H.get_video_dims(video_file)
  local out = assert(io.open(ass_file, "w"))
  H.build_ass(out, events, opts.ass_header, opts)
  out:close()
  print("Generated: " .. ass_file)

  -- 5. Bake those subtitles into the final video
  H.run_ffmpeg(video_file, ass_file, out_video)
  print("Done. Saved captioned video to: " .. out_video)
end

-- ============================================================================
-- Validation
-- ============================================================================

H.validate_events = function(events)
  assert(type(events) == "table" and #events > 0, "No key events found")

  for i = 1, #events do
    assert(type(events[i].ms) == "number", "Event " .. i .. " missing numeric ms")
  end

  for i = 1, #events - 1 do
    assert(events[i].ms <= events[i + 1].ms, "Events must be sorted by timestamp")
  end
end

-- ============================================================================
-- Normalize keys
-- ============================================================================

H.vim_overrides = {
  Backspace = "BS",
  Delete = "Del",
  Enter = "CR",
  Escape = "Esc",
  Ctrl = "C",
  Alt = "A",
  Shift = "S",
}
H.vim_normalization = function(key)
  local parts = vim.split(key, "+", { plain = true })

  for i = 1, #parts do
    parts[i] = H.vim_overrides[parts[i]] or parts[i]
  end

  if #parts == 1 and vim.fn.strchars(parts[1]) == 1 then return parts[1] end

  return "<" .. table.concat(parts, "-") .. ">"
end

H.icon_overrides = {
  Backspace = "⌫",
  Delete = "⌦",
  Ctrl = "^",
  Alt = "⌥",
  Shift = "⇧",
  Down = "↓",
  PageDown = "⇟",
  Up = "↑",
  PageUp = "⇞",
  Left = "←",
  Right = "→",
  Space = "␣",
  Enter = "⏎",
  Escape = "󱊷",
  Tab = "⇥",
}
H.icon_normalization = function(key)
  local parts = {}

  for j, k in ipairs(vim.split(key, "+", { plain = true })) do
    parts[j] = H.icon_overrides[k] or k
  end

  return table.concat(parts, "")
end

-- ============================================================================
-- Iterator yields windows containing keys and how long they should be shown
-- ============================================================================

-- Given a series af keypress events:
--
--    Key     Ms
--    L      100
--    O      200
--    G      300
--    I     1500
--    N     1600
--
-- Generate a series of "windows" that ASS requires:
--
--   1. Start timestamp in centiseconds
--   2. Stop timestapme in centiseconds
--   3. The text to be shown onscreen during this interval
--
-- Using an inactivity timer of 1000ms, the above events should generate
-- the following ASS windows:
--
--   Start   Stop   Text
--    100     200    L
--    200     300    LO
--    300    1300    LOG   (inactivity timer exceeded)
--   1500    1600    I
--   1600    2600    IN    (inactivity timer exceeded)
--
H.window_iterator = function(events, opts)
  local inactivity_timer = opts.inactivity_timer_ms or 1000
  local max_keys = math.max(opts.max_keys_onscreen, 1) or 10

  local i, n = 0, #events
  local session_start = 1

  return function()
    i = i + 1
    if i > n then return nil end

    local current = events[i]
    local next_ms = events[i + 1] and events[i + 1].ms

    local window_start = math.max(session_start, i - max_keys + 1)
    local is_truncated = window_start > session_start

    local show_until
    if next_ms and next_ms - current.ms <= inactivity_timer then
      show_until = next_ms
    else
      show_until = current.ms + inactivity_timer
      session_start = i + 1
    end

    return window_start, i, show_until, is_truncated
  end
end

-- ============================================================================
-- ASS helpers
-- ============================================================================

H.ms_to_ass = function(ms)
  local h = math.floor(ms / 3600000)
  ms = ms % 3600000

  local m = math.floor(ms / 60000)
  ms = ms % 60000

  local s = math.floor(ms / 1000)
  ms = ms % 1000

  local cs = math.floor(ms / 10)

  return string.format("%d:%02d:%02d.%02d", h, m, s, cs)
end

H.ass_escape = function(text) return text:gsub("\\", "\\\\"):gsub("{", "\\{"):gsub("}", "\\}") end

H.opacity_to_ass_alpha = function(opacity)
  local alpha = math.floor((1 - opacity) * 255 + 0.5)
  return string.format("%02X", alpha)
end

H.window_text = function(events, first, last, is_truncated, style)
  local buf = {}

  if is_truncated then buf[#buf + 1] = "…" end

  for i = first, last - 1 do
    buf[#buf + 1] = H.ass_escape(events[i].key)
  end

  local last_key = H.ass_escape(events[last].key)
  buf[#buf + 1] = string.format("{\\c%s}%s{\\r}", style.highlight_color, last_key)

  return table.concat(buf, " ")
end

-- ============================================================================
-- ASS builder
-- ============================================================================

H.build_ass = function(f, events, template, opts)
  local out = function(s) f:write(s, "\n") end

  -- Write header substituting {{...}} placeholders
  local header = template:gsub("{{(.-)}}", function(placeholder)
    local v = opts[placeholder]
    assert(v ~= nil, "Missing template value: " .. placeholder)
    return tostring(v)
  end)
  out(header)

  local alpha = H.opacity_to_ass_alpha(opts.background_opacity)
  local next_window = H.window_iterator(events, opts)

  -- Write subtitle window segments
  for first, last, show_until, is_truncated in next_window do
    local text = H.window_text(events, first, last, is_truncated, opts)
    text = string.format("{\\bord3\\shad0\\3c&H000000&\\3a&H%s&}%s", alpha, text)
    out(string.format("Dialogue: 0,%s,%s,Keys,,0,0,0,,%s", H.ms_to_ass(events[last].ms), H.ms_to_ass(show_until), text))
  end
end

-- ============================================================================
-- External helpers
-- ============================================================================

H.get_video_dims = function(file)
  local cmd = string.format(
    "ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 %s",
    vim.fn.shellescape(file)
  )

  local handle = assert(io.popen(cmd), "Failed to execute ffprobe")
  local result = handle:read("*a")
  local ok, _, code = handle:close()
  assert(ok, "ffprobe failed with exit code " .. tostring(code))

  local w, h = result:match("^(%d+)x(%d+)%s*$")
  assert(w and h, "Could not determine video dimensions from ffprobe output")

  return w, h
end

H.run_ffmpeg = function(video_file, ass_file, out_video)
  local filter = "ass=" .. ass_file

  local cmd = string.format(
    "ffmpeg -y -i %s -vf %s -c:a copy %s",
    vim.fn.shellescape(video_file),
    vim.fn.shellescape(filter),
    vim.fn.shellescape(out_video)
  )

  print("Running ffmpeg...")
  local ok, _, code = os.execute(cmd)
  assert(ok, "FFmpeg failed with exit code " .. tostring(code))
end

-- ============================================================================
-- CLI and Environment parsing
-- ============================================================================

H.flag_handlers = {
  ["font"] = function(v, opts) opts.font = v end,
  ["font-size"] = function(v, opts) opts.font_size = tonumber(v) end,
  ["key-normalization"] = function(v, opts) opts.key_normalization = v .. "_normalization" end,
  ["inactivity-timer-ms"] = function(v, opts) opts.inactivity_timer_ms = tonumber(v) end,
  ["max-keys-onscreen"] = function(v, opts) opts.max_keys_onscreen = tonumber(v) end,
  ["margin-left"] = function(v, opts) opts.margin_left = tonumber(v) end,
  ["margin-right"] = function(v, opts) opts.margin_right = tonumber(v) end,
  ["margin-vertical"] = function(v, opts) opts.margin_vertical = tonumber(v) end,
  ["highlight-color"] = function(v, opts)
    -- expect RRGGBB
    assert(#v == 6 and v:match("^[0-9A-Fa-f]+$"), "highlight-color must be RRGGBB")
    -- convert RGB to ASS BGR
    local r, g, b = v:sub(1, 2), v:sub(3, 4), v:sub(5, 6)
    opts.highlight_color = string.format("&H%s%s%s&", b, g, r)
  end,
  ["background-opacity"] = function(v, opts)
    local n = tonumber(v)
    assert(n and n >= 0 and n <= 1, "background-opacity must be between 0 and 1")
    opts.background_opacity = n
  end,
}

H.parse_env = function()
  local opts = {}

  for opt, handler in pairs(H.flag_handlers) do
    local env_name = "KEYTAPE_" .. opt:gsub("-", "_"):upper()
    local value = os.getenv(env_name)
    if value then handler(value, opts) end
  end

  return opts
end

H.parse_cli = function()
  if #arg < 2 then error("usage: keytape keylog video [--flag=value]") end

  local opts = {}

  for i = 3, #arg do
    local name, value = arg[i]:match("^%-%-(.-)=(.+)$")
    if not name then error("Invalid argument: " .. arg[i]) end

    local handler = H.flag_handlers[name]
    if not handler then error("Unknown flag: --" .. name) end

    handler(value, opts)
  end

  return arg[1], arg[2], opts
end

-- ============================================================================
-- Run main
-- ============================================================================

main()

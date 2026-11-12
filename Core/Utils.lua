-- Core/Utils.lua : generic helpers (no game logic).
local ADB = ADB
local min, max, format = math.min, math.max, string.format

function ADB.Clamp(v, lo, hi) return max(lo, min(hi, v)) end

-- Strips control chars and "|" (chat escape), trims.
function ADB.CleanName(s)
    s = tostring(s or "")
    s = s:gsub("%c", "")
    s = s:gsub("|", "")
    return strtrim(s)
end

-- Percent-escapes every char matching `set` (a Lua char-class pattern).
function ADB.Escape(s, set)
    return (tostring(s):gsub(set, function(c) return format("%%%02X", c:byte()) end))
end
function ADB.Encode(s) return ADB.Escape(s, "[%%;]") end
function ADB.Decode(s)
    return (s:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end))
end

-- UTF-8 safe splitter (never cuts inside a multibyte sequence).
function ADB.SplitUtf8(s, size)
    local t, i = {}, 1
    while i <= #s do
        local j = min(i + size - 1, #s)
        while j < #s and j > i and (s:byte(j + 1) or 0) >= 0x80 and (s:byte(j + 1) or 0) < 0xC0 do
            j = j - 1
        end
        t[#t + 1] = s:sub(i, j)
        i = j + 1
    end
    return t
end

function ADB.IconTexture(icon)
    if tonumber(icon) then return tonumber(icon) end
    return "Interface\\Icons\\" .. icon
end

function ADB.FormatMoney(copper)
    copper = math.floor(tonumber(copper) or 0)
    return format("|cffffd700%d Po|r |cffc7c7cf%d Pa|r |cffeda55f%d Pc|r",
        math.floor(copper / 10000), math.floor((copper % 10000) / 100), copper % 100)
end

function ADB.Print(msg)
    DEFAULT_CHAT_FRAME:AddMessage("|cff9d6bff[Brumes]|r " .. msg)
end

-- Decorator: replaces tbl[key] with wrapper(original, ...). Load order = wrap order.
function ADB.Wrap(tbl, key, wrapper)
    local orig = tbl[key]
    tbl[key] = function(...) return wrapper(orig, ...) end
end

-- Returns a safe icon name/fileID; falls back to the question-mark icon.
function ADB.SanitizeIcon(icon)
    icon = tostring(icon or "")
    if #icon == 0 or #icon > 40 or icon:find("[^%w_]") then return "INV_Misc_QuestionMark" end
    return icon
end
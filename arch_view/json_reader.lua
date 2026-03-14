local common = require("arch_view.common")

local json_reader = {}

local function _build_error(text, index)
    error("json decode error at " .. tostring(index) .. ": " .. tostring(text))
end

local function _char_at(text, index)
    return string.sub(text, index, index)
end

local function _is_whitespace(ch)
    return ch == " " or ch == "\n" or ch == "\r" or ch == "\t"
end

local function _skip_whitespace(text, index)
    local cursor = index
    while cursor <= #text and _is_whitespace(_char_at(text, cursor)) do
        cursor = cursor + 1
    end
    return cursor
end

local function _parse_string(text, index)
    local cursor = index + 1
    local parts = {}
    while cursor <= #text do
        local ch = _char_at(text, cursor)
        if ch == "\"" then
            return table.concat(parts), cursor + 1
        end
        if ch == "\\" then
            local next_ch = _char_at(text, cursor + 1)
            if next_ch == "\"" or next_ch == "\\" or next_ch == "/" then
                parts[#parts + 1] = next_ch
            elseif next_ch == "b" then
                parts[#parts + 1] = "\b"
            elseif next_ch == "f" then
                parts[#parts + 1] = "\f"
            elseif next_ch == "n" then
                parts[#parts + 1] = "\n"
            elseif next_ch == "r" then
                parts[#parts + 1] = "\r"
            elseif next_ch == "t" then
                parts[#parts + 1] = "\t"
            else
                _build_error("unsupported escape sequence", cursor)
            end
            cursor = cursor + 2
        else
            parts[#parts + 1] = ch
            cursor = cursor + 1
        end
    end
    _build_error("unterminated string", index)
end

local function _digit_value(ch)
    local byte = string.byte(ch or "")
    if byte == nil then
        return nil
    end
    local digit = byte - 48
    if digit < 0 or digit > 9 then
        return nil
    end
    return digit
end

local function _parse_number(text, index)
    local cursor = index
    local sign = 1
    if _char_at(text, cursor) == "-" then
        sign = -1
        cursor = cursor + 1
    end

    local int_value = 0
    local digit_count = 0
    while cursor <= #text do
        local digit = _digit_value(_char_at(text, cursor))
        if digit == nil then
            break
        end
        int_value = int_value * 10 + digit
        digit_count = digit_count + 1
        cursor = cursor + 1
    end
    if digit_count == 0 then
        _build_error("invalid number", index)
    end

    local value = int_value
    if _char_at(text, cursor) == "." then
        cursor = cursor + 1
        local divisor = 1
        local fraction_count = 0
        while cursor <= #text do
            local digit = _digit_value(_char_at(text, cursor))
            if digit == nil then
                break
            end
            value = value * 10 + digit
            divisor = divisor * 10
            fraction_count = fraction_count + 1
            cursor = cursor + 1
        end
        if fraction_count == 0 then
            _build_error("invalid fractional number", index)
        end
        value = value / divisor
    end

    local exponent = 0
    local exp_sign = 1
    local exp_marker = _char_at(text, cursor)
    if exp_marker == "e" or exp_marker == "E" then
        cursor = cursor + 1
        local exp_ch = _char_at(text, cursor)
        if exp_ch == "-" then
            exp_sign = -1
            cursor = cursor + 1
        elseif exp_ch == "+" then
            cursor = cursor + 1
        end
        local exp_count = 0
        while cursor <= #text do
            local digit = _digit_value(_char_at(text, cursor))
            if digit == nil then
                break
            end
            exponent = exponent * 10 + digit
            exp_count = exp_count + 1
            cursor = cursor + 1
        end
        if exp_count == 0 then
            _build_error("invalid exponent", index)
        end
    end

    value = sign * value
    if exponent ~= 0 then
        value = value * (10 ^ (exp_sign * exponent))
    end
    return value, cursor
end

local function _parse_literal(text, index, literal, value)
    if string.sub(text, index, index + #literal - 1) ~= literal then
        _build_error("invalid literal", index)
    end
    return value, index + #literal
end

local _parse_value

local function _parse_array(text, index)
    local cursor = _skip_whitespace(text, index + 1)
    local values = {}
    if _char_at(text, cursor) == "]" then
        return values, cursor + 1
    end
    while cursor <= #text do
        local value
        value, cursor = _parse_value(text, cursor)
        values[#values + 1] = value
        cursor = _skip_whitespace(text, cursor)
        local ch = _char_at(text, cursor)
        if ch == "]" then
            return values, cursor + 1
        end
        if ch ~= "," then
            _build_error("expected ',' or ']'", cursor)
        end
        cursor = _skip_whitespace(text, cursor + 1)
    end
    _build_error("unterminated array", index)
end

local function _parse_object(text, index)
    local cursor = _skip_whitespace(text, index + 1)
    local object = {}
    if _char_at(text, cursor) == "}" then
        return object, cursor + 1
    end
    while cursor <= #text do
        if _char_at(text, cursor) ~= "\"" then
            _build_error("expected string key", cursor)
        end
        local key
        key, cursor = _parse_string(text, cursor)
        cursor = _skip_whitespace(text, cursor)
        if _char_at(text, cursor) ~= ":" then
            _build_error("expected ':' after key", cursor)
        end
        cursor = _skip_whitespace(text, cursor + 1)
        object[key], cursor = _parse_value(text, cursor)
        cursor = _skip_whitespace(text, cursor)
        local ch = _char_at(text, cursor)
        if ch == "}" then
            return object, cursor + 1
        end
        if ch ~= "," then
            _build_error("expected ',' or '}'", cursor)
        end
        cursor = _skip_whitespace(text, cursor + 1)
    end
    _build_error("unterminated object", index)
end

function _parse_value(text, index)
    local cursor = _skip_whitespace(text, index)
    local ch = _char_at(text, cursor)
    if ch == "\"" then
        return _parse_string(text, cursor)
    end
    if ch == "{" then
        return _parse_object(text, cursor)
    end
    if ch == "[" then
        return _parse_array(text, cursor)
    end
    if ch == "t" then
        return _parse_literal(text, cursor, "true", true)
    end
    if ch == "f" then
        return _parse_literal(text, cursor, "false", false)
    end
    if ch == "n" then
        return _parse_literal(text, cursor, "null", nil)
    end
    if ch == "-" or common.to_integer(ch) ~= nil then
        return _parse_number(text, cursor)
    end
    _build_error("unexpected token", cursor)
end

function json_reader.decode(text)
    local raw_text = tostring(text or "")
    local value, cursor = _parse_value(raw_text, 1)
    cursor = _skip_whitespace(raw_text, cursor)
    if cursor <= #raw_text then
        _build_error("trailing content", cursor)
    end
    return value
end

return json_reader

-- Session to Milestone Unit Converter
-- Protocol: Converter<ConverterState, DataValueNumber, DataValueString>
--
-- Input: sessionSeconds (DataValueNumber - session duration in seconds; legacy: totalSessionSeconds)
-- Output: DataValueString ("m" for minutes, "hr" for hours)
--
-- Minutes: 600-3599 seconds (10m through 50m)
-- Hours: 3600+ seconds (1hr through 24hr+)
--
-- Usage in Rive Editor:
-- 1. Add as a Converter script (Number input, String output)
-- 2. Set input to: sessionSeconds (View Model property)
-- 3. Bind output to milestone unit text run (separate from the number)

return function()
    return {
        convert = function(self, input): DataValueString
            local raw = type(input) == "table" and input.value or input
            local sec = math.floor(tonumber(raw) or 0)
            local out = DataValue.string()
            if sec < 300 then
                out.value = ""
                return out
            end
            out.value = sec >= 3600 and "hr" or "m"
            return out
        end
    }
end

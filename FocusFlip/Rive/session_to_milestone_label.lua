-- Session to Milestone Number Converter
-- Protocol: Converter<ConverterState, DataValueNumber, DataValueString>
--
-- Input: sessionSeconds (DataValueNumber - session duration in seconds; legacy: totalSessionSeconds)
-- Output: DataValueString (milestone number only: "10", "15", "1", "24", etc.)
-- Unit ("m" / "hr") is handled by session_to_milestone_unit.lua
--
-- Derived from FocusFlip/Models/Milestone.swift (Milestone.allMilestones)
-- Keep in sync when adding or changing milestones.
--
-- Usage in Rive Editor:
-- 1. Add as a Converter script (Number input, String output)
-- 2. Set input to: sessionSeconds (View Model property)
-- 3. Bind output to milestone number text run

type LabelRow = { upper: number, value: string }

local thresholds: { LabelRow } = {
    { upper = 600, value = "5" },     -- 5m: 300-599 (streak achieved)
    { upper = 900, value = "10" },
    { upper = 1200, value = "15" },
    { upper = 1800, value = "20" },
    { upper = 2400, value = "30" },
    { upper = 3000, value = "40" },
    { upper = 3600, value = "50" },
    { upper = 7200, value = "1" },
    { upper = 10800, value = "2" },
    { upper = 14400, value = "3" },
    { upper = 18000, value = "4" },
    { upper = 21600, value = "5" },
    { upper = 25200, value = "6" },
    { upper = 28800, value = "7" },
    { upper = 32400, value = "8" },
    { upper = 36000, value = "9" },
    { upper = 39600, value = "10" },
    { upper = 43200, value = "11" },
    { upper = 46800, value = "12" },
    { upper = 50400, value = "13" },
    { upper = 54000, value = "14" },
    { upper = 57600, value = "15" },
    { upper = 61200, value = "16" },
    { upper = 64800, value = "17" },
    { upper = 68400, value = "18" },
    { upper = 72000, value = "19" },
    { upper = 75600, value = "20" },
    { upper = 79200, value = "21" },
    { upper = 82800, value = "22" },
    { upper = 86400, value = "23" },
    { upper = 86401, value = "24" },
    { upper = 999999999, value = "24" },
}

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
            for _, row in ipairs(thresholds) do
                if sec < row.upper then
                    out.value = row.value
                    return out
                end
            end
            out.value = "24"
            return out
        end
    }
end

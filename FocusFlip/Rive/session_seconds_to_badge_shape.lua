-- Session Seconds to Badge Shape Converter
-- Protocol: Converter<ConverterState, DataValueNumber, DataValueNumber>
--
-- Input: sessionSeconds (this session's duration in seconds)
-- Output: DataValueNumber (badge selector code)
--
-- NOTE: Your current Rive state machine expects the *old* selector codes:
--   - Minutes use 10/15/20/30/40/50
--   - Hours use 100/200/300/.../2400
--   - 0 means "no badge" (under 10m, including 5m)
--
-- Usage in Rive Editor:
-- 1. Add as a Converter script (Number input, Number output)
-- 2. Set input to: sessionSeconds (View Model property)
-- 3. Bind output to badge shape selection

type BadgeRow = { upper: number, badge: number }

local thresholds: { BadgeRow } = {
    { upper = 600, badge = 0 },       -- <10m: no badge (includes 5m)
    { upper = 900, badge = 10 },      -- 10m: 600-899
    { upper = 1200, badge = 15 },     -- 15m: 900-1199
    { upper = 1800, badge = 20 },     -- 20m: 1200-1799
    { upper = 2400, badge = 30 },     -- 30m: 1800-2399
    { upper = 3000, badge = 40 },     -- 40m: 2400-2999
    { upper = 3600, badge = 50 },     -- 50m: 3000-3599
    { upper = 7200, badge = 100 },    -- 1hr: 3600-7199
    { upper = 10800, badge = 200 },   -- 2hr: 7200-10799
    { upper = 14400, badge = 300 },   -- 3hr: 10800-14399
    { upper = 18000, badge = 400 },   -- 4hr: 14400-17999
    { upper = 21600, badge = 500 },   -- 5hr: 18000-21599
    { upper = 25200, badge = 600 },   -- 6hr: 21600-25199
    { upper = 28800, badge = 700 },   -- 7hr: 25200-28799
    { upper = 32400, badge = 800 },   -- 8hr: 28800-32399
    { upper = 36000, badge = 900 },   -- 9hr: 32400-35999
    { upper = 39600, badge = 1000 },  -- 10hr: 36000-39599
    { upper = 43200, badge = 1100 },  -- 11hr: 39600-43199
    { upper = 46800, badge = 1200 },  -- 12hr: 43200-46799
    { upper = 50400, badge = 1300 },  -- 13hr: 46800-50399
    { upper = 54000, badge = 1400 },  -- 14hr: 50400-53999
    { upper = 57600, badge = 1500 },  -- 15hr: 54000-57599
    { upper = 61200, badge = 1600 },  -- 16hr: 57600-61199
    { upper = 64800, badge = 1700 },  -- 17hr: 61200-64799
    { upper = 68400, badge = 1800 },  -- 18hr: 64800-68399
    { upper = 72000, badge = 1900 },  -- 19hr: 68400-71999
    { upper = 75600, badge = 2000 },  -- 20hr: 72000-75599
    { upper = 79200, badge = 2100 },  -- 21hr: 75600-79199
    { upper = 82800, badge = 2200 },  -- 22hr: 79200-82799
    { upper = 86400, badge = 2300 },  -- 23hr: 82800-86399
    { upper = 86401, badge = 2400 },  -- 24hr: 86400-86400
    { upper = 999999999, badge = 2400 }, -- 24hr+: 86401+
}

return function()
    return {
        convert = function(self, input): DataValueNumber
            local raw = type(input) == "table" and input.value or input
            local sec = math.floor(tonumber(raw) or 0)
            local out = DataValue.number()
            for _, row in ipairs(thresholds) do
                if sec < row.upper then
                    out.value = row.badge
                    return out
                end
            end
            out.value = 2400
            return out
        end
    }
end

-- The lib tags its own errors with this, which says nothing once the plugin is the one showing them
local LIB_TAG: string = "[Litmus]: "

local words = {}

function words.untagged(message: string): string
    if string.sub(message, 1, #LIB_TAG) == LIB_TAG then
        return string.sub(message, #LIB_TAG + 1)
    end

    return message
end

function words.plain(text: string): string
    return (string.gsub(text, "\27%[[%d;]*m", ""))
end

function words.plural(count: number, noun: string): string
    return `{count} {noun}{if count == 1 then "" else "s"}`
end

-- How a set of tests went, in a few words
function words.testNote(total: number, failed: number): string
    return if failed == 0 then words.plural(total, "test") else `{total - failed} of {total} passed`
end

return words

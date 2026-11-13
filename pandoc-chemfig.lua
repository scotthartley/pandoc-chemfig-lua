-- Pandoc Lua filter for figure/image processing.
-- Supports alternate LaTeX float environments (scheme, chart, graph, etc.)
-- via the image class attribute. Cross-references (@id or @ref:id) are
-- replaced with sequential numbers or LaTeX \ref{} commands.
-- Also supports wrapfig (wwidth/wpos), float placement (lpos),
-- LaTeX type suffix (lts), and custom caption formats via metadata.
-- The `disable_pandoc_chemfig_wrap` metadata flag disables wrapfloat
-- wrapping document-wide, falling back to normal LaTeX float placement.

-- Map from identifier to sequential number string (e.g. "s:1" to "1").
local known_ids = {}

-- Map from class name to running integer counter.
local known_classes = {}

-- Map from class name to Pandoc inlines caption format template.
-- Populated from metadata or built as a default on first use.
local caption_formats = {}

-- Set from the `disable_pandoc_chemfig_wrap` metadata flag. When true,
-- wwidth/wpos are ignored and figures use normal LaTeX float placement.
local disable_wrap = false

-- Stringify a list of Pandoc Inline elements to plain text.
-- Returns "" for nil or empty input.
local function str_of (inlines)
    if not inlines or #inlines == 0 then return "" end
    return pandoc.utils.stringify(pandoc.Span(inlines))
end

-- Interpret a metadata value as a boolean flag. Accepts MetaBool as-is and
-- treats the strings "false", "no", "off", "0" and "" as false so that
-- `--metadata=key:false` behaves as expected.
local function meta_flag (value)
    if value == nil then return false end
    if type(value) == "boolean" then return value end
    local text = pandoc.utils.stringify(value):lower()
    return not (text == "" or text == "false" or text == "no"
                or text == "off" or text == "0")
end

-- Convert a pandoc-style image dimension (e.g. "3.5in", "50%", "300px",
-- "300") into a LaTeX length. Percentages become a fraction of `relative_to`
-- (\linewidth for width, \textheight for height), mirroring pandoc's own
-- LaTeX writer. Pixel and unitless values are converted to inches at 96 dpi.
-- Anything else (cm, mm, pt, em, \linewidth, ...) is passed through as-is.
local function latex_dimension (value, relative_to)
    if not value or value == "" then return nil end
    local num, unit = value:match("^%s*([%d%.]+)%s*(%S*)%s*$")
    if not num then return value end
    if unit == "%" then
        return string.format("%g", tonumber(num) / 100) .. relative_to
    elseif unit == "" or unit == "px" then
        return string.format("%g", tonumber(num) / 96) .. "in"
    elseif unit == "inch" then
        return num .. "in"
    end
    return num .. unit
end

-- Clone a caption format template and replace "#" with the given number.
local function insert_number (fmt_inlines, num)
    local label = pandoc.Inlines(fmt_inlines):clone()
    return label:walk({
        Str = function (s)
            return pandoc.Str(s.text:gsub("#", tostring(num)))
        end
    })
end

-- Replace citation references (e.g. @s:1 or @ref:s:1) with the figure's
-- sequence number. For LaTeX, emits \ref{}. Unmatched citations are left
-- unchanged for citeproc to handle.
local function parse_refs (el)
    local cite_id = el.citations[1].id
    local id_tag = cite_id:match("^ref:(.+)$") or cite_id

    if known_ids[id_tag] then
        if FORMAT == "latex" then
            return pandoc.RawInline("latex", "\\ref{" .. id_tag .. "}")
        else
            return pandoc.Str(known_ids[id_tag])
        end
    end
end

-- Process each Figure block to register its id, assign a sequential number,
-- and emit format-specific output.
-- For LaTeX: replaces the Figure with a raw Para containing the appropriate
-- float environment (scheme, wrapfloat, etc.).
-- For other formats: prepends a formatted label (e.g. "Scheme 1.") to the
-- figure caption.
local function process_images (el)
    local fig_attrs = el.attr
    local fig_caption = el.caption
    local image_id = fig_attrs.identifier

    -- Extract the Image from the Figure's content.
    local plain = el.content[1]
    if not plain or plain.t ~= "Plain" then return nil end
    local image = plain.content[1]
    if not image or image.t ~= "Image" then return nil end

    local image_attrs = image.attr
    local image_class = image_attrs.classes[1]
    local image_caption = image.caption
    local image_src = image.src

    -- Skip figures without a class or without an id.
    if not image_class or image_class == "" then return nil end
    if not image_id or image_id == "" then return nil end

    -- Flatten image attribute pairs into a lookup table.
    local keys = {}
    for _, pair in ipairs(image_attrs.attributes) do
        keys[pair[1]] = pair[2]
    end

    -- Assign the next sequential number for this class and register the id.
    known_classes[image_class] = (known_classes[image_class] or 0) + 1
    known_ids[image_id] = tostring(known_classes[image_class])

    -- Determine alt text for \includegraphics. Only use the image alt text
    -- when it differs from the figure caption to avoid redundancy.
    local fig_cap_text = ""
    local fig_cap_block = fig_caption and fig_caption.long and fig_caption.long[1]
    if fig_cap_block and (fig_cap_block.t == "Plain" or fig_cap_block.t == "Para") then
        fig_cap_text = str_of(fig_cap_block.content)
    end
    local img_cap_text = str_of(image_caption)
    local alt_text = (img_cap_text ~= fig_cap_text) and img_cap_text or ""

    -- Read optional LaTeX-specific attributes:
    --   wwidth: wrapfloat width (triggers wrapping)
    --   wpos:   wrapfloat position (default "r")
    --   lpos:   float placement specifier (e.g. "htbp")
    --   lts:    type suffix appended to class (e.g. "*" for "scheme*")
    --   width/height: image size passed to \includegraphics
    -- Wrapping and placement are mutually exclusive; wrapping takes priority.
    local latex_wrap = false
    local latex_size = nil
    local latex_wrap_pos = "r"
    local latex_fig_place = false
    local latex_fig_pos = nil
    local latex_suffix = ""

    if keys["wwidth"] and not disable_wrap then
        latex_wrap = true
        latex_size = keys["wwidth"]
    end
    if keys["wpos"] then latex_wrap_pos = keys["wpos"] end
    if keys["lpos"] then
        latex_fig_place = true
        latex_fig_pos = keys["lpos"]
    end
    if keys["lts"] then latex_suffix = keys["lts"] end

    local float_name = image_class .. latex_suffix

    if FORMAT == "latex" then

        -- 1. Build \caption{...} as a list of inlines
        local caption_inlines = {}
        local cap_block = fig_caption and fig_caption.long and fig_caption.long[1]
        if cap_block and (cap_block.t == "Plain" or cap_block.t == "Para") then
            local cap_content = cap_block.content
            if #cap_content > 0 then
                caption_inlines[#caption_inlines + 1] = pandoc.RawInline("latex", "\\caption{")
                for _, node in ipairs(cap_content) do
                    caption_inlines[#caption_inlines + 1] = node
                end
                caption_inlines[#caption_inlines + 1] = pandoc.RawInline("latex", "}")
            end
        end

        -- \includegraphics options: width/height (pandoc-style) and alt text.
        local gfx_opts = {}
        local width = latex_dimension(keys["width"], "\\linewidth")
        local height = latex_dimension(keys["height"], "\\textheight")
        if width then gfx_opts[#gfx_opts + 1] = "width=" .. width end
        if height then gfx_opts[#gfx_opts + 1] = "height=" .. height end
        if width and height then gfx_opts[#gfx_opts + 1] = "keepaspectratio" end
        if alt_text ~= "" then gfx_opts[#gfx_opts + 1] = "alt={" .. alt_text .. "}" end
        local alt_opt = table.concat(gfx_opts, ",")
        local src = image_src

        -- 2. Assemble raw LaTeX
        local pieces = {}

        if latex_wrap then
            pieces[#pieces + 1] = pandoc.RawInline("latex",
                "\n\\begin{wrapfloat}{" .. float_name .. "}{" .. latex_wrap_pos .. "}{" .. latex_size .. "}" ..
                "\n\\centering\n\\includegraphics[" .. alt_opt .. "]{" .. src .. "}\n")
            for _, node in ipairs(caption_inlines) do pieces[#pieces + 1] = node end
            pieces[#pieces + 1] = pandoc.RawInline("latex",
                "\n\\label{" .. image_id .. "}\n\\end{wrapfloat}\n")

        elseif latex_fig_place then
            pieces[#pieces + 1] = pandoc.RawInline("latex",
                "\n\\begin{" .. float_name .. "}[" .. latex_fig_pos .. "]" ..
                "\n\\centering\n\\includegraphics[" .. alt_opt .. "]{" .. src .. "}\n")
            for _, node in ipairs(caption_inlines) do pieces[#pieces + 1] = node end
            pieces[#pieces + 1] = pandoc.RawInline("latex",
                "\n\\label{" .. image_id .. "}\n\\end{" .. float_name .. "}\n")

        else
            pieces[#pieces + 1] = pandoc.RawInline("latex",
                "\n\\begin{" .. float_name .. "}" ..
                "\n\\centering\n\\includegraphics[" .. alt_opt .. "]{" .. src .. "}\n")
            for _, node in ipairs(caption_inlines) do pieces[#pieces + 1] = node end
            pieces[#pieces + 1] = pandoc.RawInline("latex",
                "\n\\label{" .. image_id .. "}\n\\end{" .. float_name .. "}\n")
        end

        return pandoc.Para(pieces)

    else
        -- Build default caption format for this class if not set from metadata.
        if not caption_formats[image_class] then
            local label = image_class:sub(1, 1):upper() .. image_class:sub(2)
            caption_formats[image_class] = pandoc.Inlines({
                pandoc.Strong({pandoc.Str(label), pandoc.Space(), pandoc.Str("#.")}),
                pandoc.Space()
            })
        end
        local fmt_inlines = caption_formats[image_class]

        local label = insert_number(fmt_inlines, known_ids[image_id])

        -- Prepend the label to the original caption.
        local orig_cap = {}
        local cap_block = fig_caption and fig_caption.long and fig_caption.long[1]
        if cap_block and (cap_block.t == "Plain" or cap_block.t == "Para") then
            orig_cap = cap_block.content
        end
        if #orig_cap > 0 then
            label:insert(pandoc.Space())
        end
        local new_cap_inlines = label .. orig_cap

        el.caption.long = {pandoc.Plain(new_cap_inlines)}
        return el
    end
end

-- Entry point: read caption format overrides from metadata, then process
-- figures and references in two passes (figures first so IDs are collected
-- before resolving references).
function Pandoc (doc)
    local meta = doc.meta

    disable_wrap = meta_flag(meta["disable_pandoc_chemfig_wrap"])

    for key, value in pairs(meta) do
        local class_name = key:match("^(.+)_caption_format$")
        if class_name then
            caption_formats[class_name] = value
        end
    end

    return doc:walk { Figure = process_images } :walk { Cite = parse_refs }
end

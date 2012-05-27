local EzSVG = {}

EzSVG.knownTags = {
    "rect", "circle", "ellipse", "line",
    "polyline", "polygon", "path", "text",
    "tspan", "textPath", "image", "svg", "g",
    "defs", "tref", "linearGradient", "radialGradient",
    "stop", "use", "symbol"
}

local mergeTable = function(dst, src)
    for k, v in pairs(src) do
        if not dst[k] then  dst[k] = src[k] end
    end
    return dst
end

local overwriteTable = function(dst, src)
    for k, v in pairs(src) do
        dst[k] = src[k]
    end
    return dst
end

local updashStyleTable = function(tbl)
    local ret = {}
    for k, v in pairs(tbl) do
        local nk = string.gsub(k, "_", "-")
        
        if k ~= nk then ret[nk] = v
        else ret[k] = v end
    end
    
    return ret
end

local serializableValue = function(k, v)
    if type(v) == "function" then return false end
    if type(k) == "number" then return true end
    if string.sub(k, 1, k.len("__")) == "__" then return false end
    return true
end

local processPropertyValues = function (tbl, run)
    for k,v in pairs(tbl) do
        if serializableValue(k, v) then
            if v ~= "" and v ~= nil then
                if type(v) == "table" then
                    tbl[k] = v:__propertyValue(k, run)
                end   
            end
        end
    end
end

local defaultGenerateFunction = function(tbl, run)
    
    if run.preflight then
        processPropertyValues(tbl, run)
        processPropertyValues(tbl["__style"], run)
    end

    local pre = string.format("<%s ", tbl["__tag"])
    local post = "/>"
    
    if tbl["__content"] then
        post = string.format(">%s</%s>", tbl["__content"]:__generate(run), tbl["__tag"])
    end
    
    if tbl["__transform"] then
        tbl[tbl["__transformProperty"]] = tbl["__transform"]:__generate(run)
    end

    local ret = pre    
    
    if not run.preflight then
        for k,v in pairs(tbl) do
            if serializableValue(k, v) then
                if v ~= "" and v ~= nil then
                    ret = string.format("%s%s=%q ", ret, k, tostring(v))
                end
            end
        end
        
        for k,v in pairs(tbl["__style"]) do
            if serializableValue(k, v) then
                if v ~= "" and v ~= nil and tbl[k] == nil then
                    ret = string.format("%s%s=%q ", ret, k, tostring(v))
                end
            end
        end
        
        if tbl["__lastRunID"] ~= run["id"] and tbl["__id"] then
            ret = string.format("%sid=%q", ret, tbl["__id"])
        end
    end
        
    ret = ret .. post
    
    run["numObjects"]  = run["numObjects"] + 1
    tbl["__lastRunID"] = run["id"]
    
    return ret
end

local transformGenerateFunction = function(tbl, run)

    if run.preflight then return "" end

    local ret = ""
    local seperator = ""
    
    for k, v in pairs(tbl["__functions"]) do
        if serializableValue(k, v) then
            local func = ""
            for i, vv in pairs(v) do
                if i == 1 then func = string.format("%s%s(", func, vv)
                elseif i == 2 then func = func .. vv
                else func = string.format("%s, %s", func, vv) end
            end
            ret = string.format("%s%s%s)", ret, seperator, func)
            seperator = "  "
        end
    end
    
    return ret
end

local defaultPropertyValueFunction = function(tbl, key, run)
    local registerReference = function()
        if run then
            table.insert(run["referencedObjects"], tbl)
        end       
    end
    
    if key == "xlink:href" then
        registerReference()
        return tbl:getRef()
    end
    
    if key == "stroke" or key == "fill" then
        registerReference()
        return tbl:getURLRef()
    end
    
    return tostring(tbl)
end

local createStyleTable = function(tag, style, doInherit)
    local ret = {}
    
    if style then
        style = updashStyleTable(style)
        mergeTable(ret, style)
    end
        
    if doInherit then mergeTable(ret, EzSVG.styles[tag]) end
    
    -- ret["__generate"] = styleGenerateFunction
    
    return ret
end

local attachTransformFunctions = function(tbl)
    tbl["rotate"] = function(tbl, angle, cx, cy)
        table.insert(tbl["__transform"]["__functions"], {"rotate", angle, cx, cy})
        return tbl
    end
    
    tbl["translate"] = function(tbl, x, y)
        table.insert(tbl["__transform"]["__functions"], {"translate", x, y})
        return tbl
    end
    
    tbl["scale"] = function(tbl, sx, sy)
        table.insert(tbl["__transform"]["__functions"], {"scale", sx, sy})
        return tbl
    end
    
    tbl["skewX"] = function(tbl, angle)
        table.insert(tbl["__transform"]["__functions"], {"skewX", angle})
        return tbl
    end
    
    tbl["skewY"] = function(tbl, angle)
        table.insert(tbl["__transform"]["__functions"], {"skewY", angle})
        return tbl
    end
    
    tbl["matrix"] = function(tbl, a, b, c, d, e, f)
        table.insert(tbl["__transform"]["__functions"], {"matrix", a, b, c, d, e, f})
        return tbl
    end
    
    tbl["__transformProperty"] = "transform"
end

local attachStyleFunctions = function(tbl)
    tbl["setStyle"] = function(tbl, key, value)
        if type(key) == "table" then
            key = updashStyleTable(key)
            overwriteTable(tbl["__style"], key)
        else
            tbl["__style"][key] = value
        end
        
        return tbl
    end
    
    tbl["mergeStyle"] = function(tbl, key, value)
        if type(key) == "table" then
            key = updashStyleTable(key)
            mergeTable(tbl["__style"], key)
        else
            if not tbl["__style"][key] then
                tbl["__style"][key] = value
            end
        end
        return tbl
    end
    
    tbl["clearStyle"] = function(tbl)
        tbl["__style"] = createStyleTable(tbl["__tag"], nil, false)
        return tbl
    end
end

local createTransformTable = function()
    local ret = {}
    
    ret["__functions"] = {}
    ret["__generate"] = transformGenerateFunction
    
    return ret
end

local currentUniqueID = 1000
local nextUniqueID = function()
    currentUniqueID = currentUniqueID + 1
    return currentUniqueID
end

local createTagTable = function(tag, style)
    local ret = {}
    
    ret["__tag"] = tag
    ret["__style"] = createStyleTable(tag, style, true)
    ret["__transform"] = createTransformTable()
    ret["__generate"] = defaultGenerateFunction
    
    attachTransformFunctions(ret)
    attachStyleFunctions(ret)
    
    local assureID = function(tbl)
        if not tbl["__id"] then
            tbl:setID("auto-unique-"..nextUniqueID())
        end
    end
    
    ret["setID"] = function(tbl, id)
        tbl["__id"] = id
        return tbl
    end
    
    ret["getID"] = function(tbl) return tbl["__id"] end
    
    ret["getRef"] = function(tbl)
        assureID(tbl)
        return "#" .. tbl["__id"]
    end
    
    ret["getURLRef"] = function(tbl)
        assureID(tbl)
        return "url(#" .. tbl["__id"] .. ")"
    end
    
    ret["__propertyValue"] = defaultPropertyValueFunction
    
    return ret
end

local createContentTable = function(content)
    local ret = {}
    ret["__text"] = content
    ret["__generate"] = function(tbl, run)
        return tbl["__text"]
    end
    
    return ret
end

local createGroupTable = function(tag, style)
    local ret = createTagTable(tag, style)
    ret["__content"] = {}
    
    ret["__content"]["__generate"] = function(tbl, run)
        local ret = ""
        for k, v in pairs(tbl) do
            if serializableValue(k, v) then
                ret = string.format("%s%s ", ret, v:__generate(run))
            end
        end
        return ret
    end
    
    ret["add"] = function(tbl, item)
        table.insert(tbl["__content"], item)
    end
    
    return ret
end

local setDefaultStyles = function(key, value, tag)
    if tag then
        EzSVG.styles[tag][key] = value
    else
        for _, v in pairs(EzSVG.styles) do
            v[key] = value
        end
    end
end

EzSVG.clearStyle = function()
    EzSVG.styles = {}
    for _, v in pairs(EzSVG.knownTags) do
        EzSVG.styles[v] = {}
    end
end

EzSVG.setStyle = function(key, value, tag)
    if type(key) == "table" then
        key = updashStyleTable(key)
        tag = value -- promote
        for k, v in pairs(key) do
            setDefaultStyles(k, v, tag)
        end
    elseif type(key) == "string" then
        setDefaultStyles(key, value, tag)
    end
end


EzSVG.Circle = function(cx, cy, r, style)
    local ret = createTagTable("circle", style)
    ret["cx"] = cx
    ret["cy"] = cy
    ret["r"] = r
    
    return ret
end

EzSVG.Ellipse = function(cx, cy, rx, ry, style)
    local ret = createTagTable("ellipse", style)
    ret["cx"] = cx
    ret["cy"] = cy
    ret["rx"] = rx
    ret["ry"] = ry
    
    return ret
end

EzSVG.Line = function(x1, y1, x2, y2, style)
    local ret = createTagTable("line", style)
    ret["x1"] = x1
    ret["y1"] = y1
    ret["x2"] = x2
    ret["y2"] = y2

    return ret
end

EzSVG.Path = function(style)
    local ret = createTagTable("path", style)
    
    ret["__d"] = {}
    ret["__generate"] = function(tbl, run)
        local d = ""
        
        if not run.preflight then        
            local seperator = ""
            for k, v in pairs(tbl["__d"]) do
                if serializableValue(k, v) then
                    d = d .. seperator .. v
                    seperator = " "
                end
            end
        end
        
        tbl["d"] = d
        
        return defaultGenerateFunction(tbl, run)
    end
    
    ret["clear"] = function(tbl)
        tbl["__d"] = {}
        return tbl
    end
    
    -- Spagetti code ahead. Not sure if I'm gonna refactor.
    -- Beware: Order of arguments is not like in SVG.
    -- Destination x/y are always first argument.
    
    ret["moveTo"] = function(tbl, x, y)
        table.insert(tbl["__d"], "m"..x..","..y)
        return tbl
    end
    
    ret["moveToA"] = function(tbl, x, y)
        table.insert(tbl["__d"], "M"..x..","..y)
        return tbl
    end
    
    ret["lineTo"] = function(tbl, x, y)
        table.insert(tbl["__d"], "l"..x..","..y)
        return tbl
    end
    
    ret["lineToA"] = function(tbl, x, y)
        table.insert(tbl["__d"], "L"..x..","..y)
        return tbl
    end
    
    ret["hLineTo"] = function(tbl, x)
        table.insert(tbl["__d"], "h"..x)
        return tbl
    end
    
    ret["hLineToA"] = function(tbl, x)
        table.insert(tbl["__d"], "H"..x)
        return tbl
    end
    
    ret["vLineTo"] = function(tbl, y)
        table.insert(tbl["__d"], "v"..y)
        return tbl
    end
    
    ret["vLineToA"] = function(tbl, y)
        table.insert(tbl["__d"], "V"..y)
        return tbl
    end
    
    ret["curveTo"] = function(tbl, x, y, x1, y1, x2, y2)
        table.insert(tbl["__d"], "c"..x1..","..y1.." "..x2..","..y2.." "..x..","..y)
        return tbl
    end
    
    ret["curveToA"] = function(tbl, x, y, x1, y1, x2, y2)
        table.insert(tbl["__d"], "C"..x1..","..y1.." "..x2..","..y2.." "..x..","..y)
        return tbl
    end
    
    ret["sCurveTo"] = function(tbl, x, y, x2, y2)
        table.insert(tbl["__d"], "s"..x2..","..y2.." "..x..","..y)
        return tbl
    end
    
    ret["sCurveToA"] = function(tbl, x, y, x2, y2)
        table.insert(tbl["__d"], "S"..x2..","..y2.." "..x..","..y)
        return tbl
    end
    
    ret["qCurveTo"] = function(tbl, x, y, x1, y1)
        table.insert(tbl["__d"], "q"..x1..","..y1.." "..x..","..y)
        return tbl
    end
    
    ret["qCurveToA"] = function(tbl, x, y, x1, y1)
        table.insert(tbl["__d"], "Q"..x1..","..y1.." "..x..","..y)
        return tbl
    end
    
    ret["sqCurveTo"] = function(tbl, x, y)
        table.insert(tbl["__d"], "t"..x..","..y)
        return tbl
    end
    
    ret["sqCurveToA"] = function(tbl, x, y)
        table.insert(tbl["__d"], "T"..x..","..y)
        return tbl
    end
    
    ret["archTo"] = function(tbl, x, y, rx, ry, rotation, largeFlag, sweepFlag)
        largeFlag = largeFlag or 0
        sweepFlag = sweepFlag or 0 -- check if this makes sense
        table.insert(tbl["__d"],
            "a"..rx..","..ry.." "..rotation.." "..
            largeFlag..","..sweepFlag.." "..x..","..y
        )
        return tbl
    end
    
    ret["archToA"] = function(tbl, x, y, rx, ry, rotation, largeFlag, sweepFlag)
        largeFlag = largeFlag or 0
        sweepFlag = sweepFlag or 0 -- check if this makes sense
        table.insert(tbl["__d"],
            "A"..rx..","..ry.." "..rotation.." "..
            largeFlag..","..sweepFlag.." "..x..","..y
        )
        return tbl
    end
        
    ret["close"] = function(tbl)
        table.insert(tbl["__d"], "Z")
        return tbl
    end
    
    return ret
end

local createPointsTagTable = function(tag, points, style)
    local ret = createTagTable(tag, style)
    
    ret["__points"] = mergeTable({}, points)
    ret["__generate"] = function(tbl, run)
        local points = ""
        local i = 0
        for _, v in pairs(tbl["__points"]) do
            if i ~= 0 then
                if i % 2 == 1 then points = points .. ","
                else points = points .. "  " end
            end
        
            points = points .. v
            i = i + 1 
        end
        tbl["points"] = points
        return defaultGenerateFunction(tbl, run)
    end
    
    ret["addPoint"] = function(tbl, x, y)
        table.insert(tbl["__points"], x)
        table.insert(tbl["__points"], y)
    end    
end

EzSVG.Polyline = function(points, style)
    return createPointsTagTable("polyline", points, style)
end

EzSVG.Polygon = function(points, style)
    return createPointsTagTable("polygon", points, style)
end

EzSVG.Rect = function(x, y, width, height, rx, ry, style)
    local ret = createTagTable("rect", style)
    
    ret["x"] = x
    ret["y"] = y
    ret["width"] = width
    ret["height"] = height
    ret["rx"] = rx
    ret["ry"] = ry
    
    return ret
end

EzSVG.Image = function(href, x, y, width, height, style)
    local ret = createTagTable("image", style)
    
    ret["xlink:href"] = href
    ret["x"] = x
    ret["y"] = y
    ret["width"] = width
    ret["height"] = height
    
    return ret
end


local createTextPathTable = function(href, text, style)
    local ret = createTagTable("textPath", style)
    
    ret["xlink:href"] = href
    ret["__content"] = text
    return ret
end

-- this somehow sucks!

EzSVG.Text = function(text, x, y, style)
    local ret = createTagTable("text", style)
    
    local contentTable
    local contentContainer = ret
    
    ret["setText"] = function(tbl, text)
        if type(text) == "string" then
            contentTable = createContentTable(text)
        else
            contentTable = text
        end
        contentContainer["__content"] = contentTable
        return tbl
    end
    
    ret:setText(text)
    
    ret["setPath"] = function(tbl, href, style)        
        contentContainer = createTextPathTable(href, contentTable, style)
        tbl["__content"] = contentContainer
        return tbl
    end
    
    ret["clearPath"] = function(tbl)
        tbl["__content"] = contentTable
        contentContainer = tbl
        return tbl
    end
    
    
    ret["x"] = x
    ret["y"] = y
        
    return ret
end

EzSVG.TextRef = function(href, style)
    local ret = createTagTable("tref", style)    
    ret["xlink:href"] = href
    
    return ret
end

EzSVG.Group = function(style)
    local ret = createGroupTable("g", style)
    return ret
end

local function numberToPercent(number)
    if type(number) == "number" then
        number = number.."%"
    end
    return number
end

local function createGradientTable(tag, userSpace, spread, style)
    local ret = createGroupTable(tag, style)
    
    ret["spreadMethod"] = spread
    
    if userSpace then
        ret["gradientUnits"] = "userSpaceOnUse"
    else
        ret["gradientUnits"] = "objectBoundingBox"
    end
    
    ret["addStop"] = function(tbl, offset, color, opacity)
        local stop = createTagTable("stop")
        stop["offset"] = numberToPercent(offset)
        stop["stop-color"] = color
        stop["stop-opacity"] = opacity
        tbl:add(stop)
        return tbl
    end
    
    ret["__transformProperty"] = "gradientTransform"
    
    return ret
end

EzSVG.LinearGradient = function(x1, y1, x2, y1, userSpace, spread,  style)
    local ret = createGradientTable("linearGradient", userSpace, spread, style)
    
    local process = numberToPercent
    if userSpace then process = function(arg) return arg end end
    
    ret["x1"] = process(x1)
    ret["y1"] = process(y1)
    ret["x2"] = process(x2)
    ret["y2"] = process(y2)
    
    return ret
end

EzSVG.RadialGradient = function(cx, cy, r, fx, fy, userSpace, spread, style)
    local ret = createGradientTable("radialGradient", userSpace, spread, style)
    
    local process = numberToPercent
    if userSpace then process = function(arg) return arg end end
    
    ret["cx"] = process(cx)
    ret["cy"] = process(cy)
    ret["r"] =  process(r)
    ret["fx"] = process(fx)
    ret["fy"] = process(fy)
    
    return ret
end

EzSVG.Use = function(href, x, y, width, height, style)
    local ret = createTagTable("use", style)
    
    ret["xlink:href"] = href
    ret["x"] = x
    ret["y"] = y
    ret["width"] = width
    ret["height"] = height
    
    return ret
end

EzSVG.Symbol = function(preserveAspectRatio, viewBox, style)
    local ret createGroupTable("symbol", style)
    
    ret["preserveAspectRatio"] = preserveAspectRatio
    ret["viewBox"] = viewBox
    
    return ret
end

local createDefs = function()
    local ret = createGroupTable("defs")
    return ret
end

local attachDefsFunctions = function(tbl)
    local defs = createDefs()
    tbl:add(defs)
    
    tbl["addDef"] = function(tbl, def)
        defs:add(def)
    end
end

local currentRunID = 0
local nextRunID = function()
    currentRunID = currentRunID + 1
    return currentRunID
end

EzSVG.Document = function(width, height, bgcolor, style)
    local ret = createGroupTable("svg", style)
    
    ret["xmlns"] = "http://www.w3.org/2000/svg"
    ret["xmlns:xlink"] = "http://www.w3.org/1999/xlink"
    
    ret["width"] = width
    ret["height"] = height
    
    if bgcolor then
        ret:add(EzSVG.Rect(0, 0, width, height, 0, 0, {
            stroke=nil,
            fill=bgcolor
        }))
    end    
    
    ret.writeTo = function(tbl, file)
    
        local createRun = function(pre)
            return {
                preflight= pre,
                referencedObjects= {},
                numObjects = 0,
                id= nextRunID()    
            }
        end
        
        preflightRun = createRun(true)
        finalRun     = createRun(false)
        
        tbl:__generate(preflightRun)
        
        -- sprint("Number of Objects: " .. preflightRun.numObjects)
        
        -- Put referenced objects not in the tree to <defs>
        for _, v in pairs(preflightRun["referencedObjects"]) do
            if v["lastRunID"] ~= preflightRun["id"] then
                tbl:addDef(v)
            end
        end
        
        local file = io.open(file, "w")
        file:write(tbl:__generate(finalRun))
        io.close(file)
    end
    
    attachDefsFunctions(ret)
    
    return ret
end

EzSVG.SVG = function(x, y, width, height, style)
    local ret = createGroupTable("svg", style)
    
    ret["width"] = width
    ret["height"] = height
        
    ret["x"] = x
    ret["y"] = y
    
    attachDefsFunctions(ret)
    
    return ret
end

EzSVG.rgb = function(r, g, b)
    return "rgb(" .. math.floor(r) .. ", " .. math.floor(g) .. ", " .. math.floor(b) ..")"
end

EzSVG.gray = function(g)
    return EzSVG.rgb(g, g, g)
end

-- init
EzSVG.clearStyle()

-- go!
return EzSVG
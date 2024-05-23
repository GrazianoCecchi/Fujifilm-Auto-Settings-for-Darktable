--[[ fujifilm_auto_settings-0.2

Apply Fujifilm film simulations, in-camera crop mode, and dynamic range.

Copyright (C) 2022 Bastian Bechtold <bastibe.dev@mailbox.org>

This program is free software; you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation; either version 2 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License along
with this program; if not, write to the Free Software Foundation, Inc.,
51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
--]]

--[[About this Plugin
Automatically applies styles that load Fujifilm film simulation LUTs,
copy crop ratios from the JPG, and correct exposure according to the
chosen dynamic range setting in camera.

Dependencies:
- exiftool (https://www.sno.phy.queensu.ca/~phil/exiftool/)
- Fuji LUTs (https://blog.sowerby.me/fuji-film-simulation-profiles/)

Debug:
To debug this script you need to launch DarkTable with this command:

"C:\Program Files\darktable\bin\darktable" -d lua > log.txt

The output can be read in the log.txt file located in the directory 
from which the startup command was launched




Based on fujifim_dynamic_range by Dan Torop.

  Film Simulations
  ----------------

Fujifilm cameras are famous for their film simulations, such as Provia
or Velvia or Classic Chrome. Indeed it is my experience that they rely
on these film simulations for accurate colors.

Darktable however does not know about or implement these film
simulations. But they are available to download from Stuart Sowerby as
3DL LUTs. (PNG LUTs are also available, but they show a strange
posterization artifact when loaded in Darktable, which the 3DLs do
not).

In order to use this plugin, you must prepare a number of styles:
- provia
- astia
- velvia
- classic_chrome
- pro_neg_standard
- pro_neg_high
- eterna
- acros_green
- acros_red
- acros_yellow
- acros
- mono_green
- mono_red
- mono_yellow
- mono
- sepia

These styles should apply the according film simulation in a method of
your choosing.

This plugin checks the image's "Film Mode" exif parameter, and applies
the appropriate style. If no matching style exists, no action is taken
and no harm is done.

  Crop Factor
  -----------

Fujifilm cameras allow in-camera cropping to one of three aspect
ratios: 2:3 (default), 16:9, and 1:1.

This plugin checks the image's "Raw Image Aspect Ratio" exif
parameter, and applies the appropriate style.

To use, prepare another four styles:
- square_crop_portrait
- square_crop_landscape
- sixteen_by_nine_crop_portrait
- sixteen_by_nine_crop_landscape

These styles should apply a square crop and a 16:9 crop to
portrait/landscape images. If no matching style exists, no action is
taken and no harm is done.

  Dynamic Range
  -------------

Fujifilm cameras have a built-in dynamic range compensation, which
(optionally automatically) reduce exposure by one or two stops, and
compensate by raising the tone curve by one or two stops. These modes
are called DR200 and DR400, respectively.

The plugin reads the raw file's "Auto Dynamic Range" or "Development
Dynamic Range" parameter, and applies one of two styles:
- DR200
- DR400

These styles should raise exposure by one and two stops, respectively,
and expand highlight latitude to make room for additional highlights.
I like to implement them with the tone equalizer in eigf mode, raising
exposure by one/two stops over the lower half of the sliders, then
ramping to zero at 0 EV. If no matching styles exist, no action is
taken and no harm is done.

These tags have been checked on a Fujifilm X-T3 and X-Pro2. Other
cameras may behave in other ways.

--]]

local dt = require "darktable"
local du = require "lib/dtutils"
local df = require "lib/dtutils.file"

du.check_min_api_version("7.0.0", "fujifilm_auto_settings")

-- return data structure for script_manager

local script_data = {}

script_data.destroy = nil -- function to destory the script
script_data.destroy_method = nil -- set to hide for libs since we can't destroy them completely yet, otherwise leave as nil
script_data.restart = nil -- how to restart the (lib) script after it's been hidden - i.e. make it visible again


local AutoDynamicRange = nil
local DevelopmentDynamicRange = nil
local AspectRatio = nil
local FilmMode = nil


local function exiftool_get(exiftool_command, RAF_filename, flag)
    
    local command ='"' .. exiftool_command .. " " .. flag .. " -t " .. RAF_filename .. '"'
    dt.print_log(command)
    local output = io.popen(command)
    local exiftool_result = output:read("*all")
    output:close()
    if #exiftool_result == 0 then
        dt.print_error("[fujifilm_auto_settings] no output returned by exiftool")
        return
    end
    local exiftool_result = string.match(exiftool_result, "\t(.*)")
    if not exiftool_result then
        dt.print_error("[fujifilm_auto_settings] could not parse exiftool output")
        return
    end
    exiftool_result = exiftool_result:match("^%s*(.-)%s*$") -- strip whitespace
    return exiftool_result
end

local function exiftool_total_get(exiftool_command, RAF_filename)
    local command ='"' .. exiftool_command .. " -AutoDynamicRange -DevelopmentDynamicRange -RawImageAspectRatio -FilmMode -t " .. RAF_filename .. '"'
    dt.print_log(command)
    
    local output = io.popen(command)

    local exiftool_result = output:read("*all")
    output:close()

    print("---------------------------------------------------------------------------------------------------------------------------")
    print(exiftool_result)
    print("---------------------------------------------------------------------------------------------------------------------------")

    if #exiftool_result == 0 then
        dt.print_error("[fujifilm_auto_settings] no output returned by exiftool")
        return
    end
    --local exiftool_result = string.match(exiftool_result, "\t(.*)")
    if not exiftool_result then
        dt.print_error("[fujifilm_auto_settings] could not parse exiftool output")
        return
    end
    exiftool_result = exiftool_result:match("^%s*(.-)%s*$") -- strip whitespace
    


-- Estrai il campo "Auto Dynamic Range"
    
    AutoDynamicRange = exiftool_result:match("Auto Dynamic Range%s+(%d+)")
    if AutoDynamicRange ~= nil then
        local P = "Auto Dynamic Range =  \t\t" .. AutoDynamicRange
        print(P)
    else 
        print("Auto Dynamic Range = \t\t---")

    end
    print("---------------------------------------------------------------------------------------------------------------------------")
-- Estrai il campo "Development Dynamic Range"
    DevelopmentDynamicRange = exiftool_result:match("Development Dynamic Range%s+(%d+)")
   
    if DevelopmentDynamicRange ~= nil then
        DevelopmentDynamicRange = DevelopmentDynamicRange .. "%"
        local P = "Development Dynamic Range =  \t" .. DevelopmentDynamicRange
        print(P)

    else 
        print("DevelopmentDynamicRange = \t---")
    end
    print("---------------------------------------------------------------------------------------------------------------------------")


    
    -- Estrai il campo "Raw Image Aspect Ratio"
    AspectRatio = exiftool_result:match("Raw Image Aspect Ratio%s+(%d+:%d+)")

    if AspectRatio ~= nil then
        local P = "Aspect Ratio =  \t\t\t" .. AspectRatio
        print(P)

    else 
        print("Aspect Ratio = \t\t\t---")

    end
    print("---------------------------------------------------------------------------------------------------------------------------")

-- Estrai il campo "Film Mode"
    -- FilmMode = exiftool_result:match("%((.-)%)")
    print(exiftool_result)
    print("+++++++++++++")
    FilmMode = exiftool_result:match("Film Mode(.+)")


    

    if FilmMode ~= nil then
        
        P = "Film Mode =  \t\t\t\t" .. FilmMode
        print(P)
    else 
        print("Film Mode = \t\t\t\t---")

    end
    print("---------------------------------------------------------------------------------------------------------------------------")

end


local function apply_style(image, style_name)
    for _, s in ipairs(dt.styles) do
        if s.name == style_name then
            dt.styles.apply(s, image)
            return
        end
    end
    dt.print_error("[fujifilm_auto_settings] could not find style " .. style_name)
end

local function apply_tag(image, tag_name)
    local tagnum = dt.tags.find(tag_name)
    if tagnum == nil then
        -- create tag if it doesn't exist
        tagnum = dt.tags.create(tag_name)
        dt.print_log("[fujifilm_auto_settings] creating tag " .. tag_name)
    end
    dt.tags.attach(tagnum, image)
end


local function detect_auto_settings(event, image)
    if image.exif_maker ~= "FUJIFILM" then
        dt.print_log("[fujifilm_auto_settings] ignoring non-Fujifilm image")
        return
    end
    -- it would be nice to check image.is_raw but this appears to not yet be set
    if not string.match(image.filename, "%.RAF$") then
        dt.print_log("[fujifilm_auto_settings] ignoring non-raw image")
        return
    end
    local exiftool_command = df.check_if_bin_exists("exiftool")

    if not exiftool_command then
        dt.print_error("[fujifilm_auto_settings] exiftool not found")
        return
    end


    exiftool_command = string.gsub( exiftool_command , "\\", "/" )

    local RAF_filename = df.sanitize_filename(tostring(image))


    --get metadata immage file
    exiftool_total_get(exiftool_command, RAF_filename)


    -- if manually chosen DR, the value is saved to Development Dynamic Range:
    if AutoDynamicRange == nil then
        AutoDynamicRange = DevelopmentDynamicRange --file_map["DevelopmentDynamicRange"] 
    end

    --print(AutoDynamicRange)
    --AutoDynamicRange = AutoDynamicRange .. '%'

    if AutoDynamicRange == "100%" then
        apply_tag(image, "DR100")
        -- default; no need to change style
    elseif AutoDynamicRange == "200%" then
        apply_style(image, "Fujifilm-Autosettings|DR200")
        apply_tag(image, "DR200")
        dt.print_log("[fujifilm_auto_settings] DR200")
    elseif AutoDynamicRange == "400%" then
        apply_style(image, "Fujifilm-Autosettings|DR400")
        apply_tag(image, "DR400")
        dt.print_log("[fujifilm_auto_settings] DR400")
    end

    -- cropmode
    if AspectRatio == "3:2" then
        apply_tag(image, "3:2")
        -- default; no need to apply style
    elseif AspectRatio == "1:1" then
        if image.width > image.height then
            apply_style(image, "Fujifilm-Autosettings|square_crop_landscape")
        else
            apply_style(image, "Fujifilm-Autosettings|square_crop_portrait")
        end
        apply_tag(image, "1:1")
        dt.print_log("[fujifilm_auto_settings] square crop")
    elseif AspectRatio == "16:9" then
        if image.width > image.height then
            apply_style(image, "Fujifilm-Autosettings|sixteen_by_nine_crop_landscape")
        else
            apply_style(image, "Fujifilm-Autosettings|sixteen_by_nine_crop_portrait")
        end
        apply_tag(image, "16:9")
        dt.print_log("[fujifilm_auto_settings] 16:9 crop")
    end
    -- filmmode
    local style_map = {
        ["Provia"] = "Fujifilm-Autosettings|provia",
        ["Astia"] = "Fujifilm-Autosettings|astia",
        ["Classic Chrome"] = "Fujifilm-Autosettings|classic_chrome",
        ["Eterna"] = "Fujifilm-Autosettings|eterna",
        ["Acros+G"] = "Fujifilm-Autosettings|acros_green",
        ["Acros+R"] = "Fujifilm-Autosettings|acros_red",
        ["Acros+Ye"] = "Fujifilm-Autosettings|acros_yellow",
        ["Acros"] = "Fujifilm-Autosettings|acros",
        ["Mono+G"] = "Fujifilm-Autosettings|mono_green",
        ["Mono+R"] = "Fujifilm-Autosettings|mono_red",
        ["Mono+Ye"] = "Fujifilm-Autosettings|mono_yellow",
        ["Mono"] = "Fujifilm-Autosettings|mono",
        ["Pro Neg Hi"] = "Fujifilm-Autosettings|pro_neg_high",
        ["Pro Neg Std"] = "Fujifilm-Autosettings|pro_neg_standard",
        ["Sepia"] = "Fujifilm-Autosettings|sepia",
        ["Velvia"] = "Fujifilm-Autosettings|velvia",
    }


    for key, value in pairs(style_map) do
        if string.find(FilmMode, key) then
            apply_style(image, value)
            apply_tag(image, key)
            dt.print_log("[fujifilm_auto_settings] film simulation " .. key)
        end
    end

    --Applico il mio stile 
    --  Contrasto locale
    --  Nitidezza
    apply_style(image, "Gra|Base")
    --apply_tag(image, "Contrasto locale)
    --apply_tag(image, "Nitidezza")
    --apply_tag(image, "Correzzione obiettivo")
    --apply_tag(image, "Riduzione rumore profilato")
    --apply_tag(image, "Bilanciamento colore RGB")
    dt.print_log("Applicato stile Gra|Base")

end

local function detect_auto_settings_multi(event, shortcut)
    local images = dt.gui.selection()
    if #images == 0 then
        dt.print(_("Please select an image"))
    else
        for _, image in ipairs(images) do
            detect_auto_settings(event, image)
        end
    end
end

local function destroy()
    dt.destroy_event("fujifilm_auto_settings", "post-import-image")
    dt.destroy_event("fujifilm_auto_settings", "shortcut")
end

if not df.check_if_bin_exists("exiftool") then
    dt.print_log("Please install exiftool to use fujifilm_auto_settings")
    error "[fujifilm_auto_settings] exiftool not found"
end

dt.register_event("fujifilm_auto_settings", "post-import-image", detect_auto_settings)

dt.register_event("fujifilm_auto_settings", "shortcut", detect_auto_settings_multi, "fujifilm_auto_settings")

dt.print_log("[fujifilm_auto_settings] loaded")

script_data.destroy = destroy

return script_data
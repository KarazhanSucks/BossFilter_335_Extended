BossFilter = LibStub("AceAddon-3.0"):NewAddon("BossFilter", "AceConsole-3.0", "AceEvent-3.0", "AceHook-3.0")

local LDB = LibStub("LibDataBroker-1.1", true)
local LDBIcon = LDB and LibStub("LibDBIcon-1.0", true)

local channels = {
    [1] = GUILD,
    [2] = RAID,
    [3] = PARTY,
    [4] = SAY,
    [5] = YELL,
    [6] = EMOTE,
}

local options = {
    name = "BossFilter",
    handler = BossFilter,
    type = "group",
    args = {
        playSound = {
            type = "toggle",
            name = "Play sound",
            desc = "Enables or disables playing sound",
            get = "getSound",
            set = "toggleSound",
            order = 1,
        },
        play = {
            type = "input",
            name = "Play",
            desc = "Plays the given ID",
			get = false,
			set = function(info, value) BossFilter:PlayYellByID(tonumber(value)) end,
            order = 2,
        },
        sendText = {
            type = "toggle",
            name = "Send text",
            desc = "Sends the text in the specified channel",
            get = "getText",
            set = "toggleText",
            order = 3,
        },
        outputChannel = {
            type = "select",
            name = "Chatchannel",
            desc = "Select where you want to output the message",
            get = "getChannel",
            set = function(info,value) BossFilter:setChannel(value) end,
            values = channels,
            disabled = function(info) return not BossFilter:getText() end,
            order = 4,
        },
        additionalOutput = {
            type = "toggle",
            name = "Additional output",
            desc = "Also outputs text in the ErrorFrame",
            get = "getAddOutput",
            set = "toggleAddOutput",
            order = 5,
        },
        search = {
            type = "input",
            name = "Search",
            desc = "Searches for the String in the database",
			get = false,
			set = function(info, value) BossFilter:Search(value) end,
            order = 6,
        },
        debug = {
            type = "toggle",
            name = "Debug Mode",
            desc = "Toggles the debugging mode",
            get = "getDebugMode",
            set = "toggleDebugMode",
            order = 7,
        },
        nameguess = {
            type = "toggle",
            name = "Name guess",
            desc = "Toggles the name guessing which makes some yells in dungeons work (due to some nice typos in blizzards output). |cffffff00[This may decrease your performance and should be toggled off in huge dungeons]|h",
            get = "getNameGuess",
            set = "toggleNameGuess",
            order = 8,
        },
        minimapIcon = {
			type = "toggle",
			name = "Minimap Icon",
			desc = "Show an Icon to open the config at the Minimap",
			get = function() return not BossFilter.db.global.minimapIcon.hide end,
			set = function(info, value) BossFilter.db.global.minimapIcon.hide = not value; LDBIcon[value and "Show" or "Hide"](LDBIcon, "BossFilter") end,
			disabled = function() return not LDBIcon end,
            order = 9,
        },
    },
}

local defaults = {
	global = {											
		useryell={},
		sound = true,
		text = true,
		addoutput = true,
		channel = "SAY",
        debug = false,
        nameguess = false,
        minimapIcon = {},
	},
}

function BossFilter:OnInitialize()
    self.db = LibStub("AceDB-3.0"):New("BossFilterDB", defaults, true)

    -- this only works after a reloadUI because the channels aren't joined yet when entering world
    self:UpdateChatChannels()
    
    LibStub("AceConfig-3.0"):RegisterOptionsTable("BossFilter", options)
    self.optionsFrame = LibStub("AceConfigDialog-3.0"):AddToBlizOptions("BossFilter", "BossFilter")
    self:RegisterChatCommand("BossFilter", "OnCmd")
    self:RawHook(nil, "SetItemRef", true)
    
    if LDB then
		local BossFilterLauncher = LDB:NewDataObject("BossFilter", {
			type = "launcher",
			icon = "Interface\\Icons\\ability_warrior_warcry",
			OnClick = function(clickedframe, button)
				BossFilter:OnLDBClick(button)
			end,
			OnTooltipShow = function(tt)
                GameTooltip:AddLine("BossFilter")
				GameTooltip:AddLine("|cff7fff7fleft|rclick: random quote")
				GameTooltip:AddLine("|cff7fff7fright|rclick: search / play")
				GameTooltip:AddLine("|cff7fff7f"..BossFilter:tablength(BossFilter.data).."|r instances supported.")
			end,
		})
        if LDBIcon then
            LDBIcon:Register("BossFilter", BossFilterLauncher, BossFilter.db.global.minimapIcon)
        end
	end
end

function BossFilter:OnEnable()
    self:RegisterEvent("CHAT_MSG_MONSTER_YELL")
	self:RegisterEvent("CHAT_MSG_MONSTER_WHISPER")
    self:RegisterEvent("CHAT_MSG_MONSTER_SAY")
    self:RegisterEvent("CHANNEL_UI_UPDATE")
end

function BossFilter:OnDisable()
    self:UnregisterEvent("CHAT_MSG_MONSTER_YELL")
	self:UnregisterEvent("CHAT_MSG_MONSTER_WHISPER")
end

function BossFilter:CHANNEL_UI_UPDATE()
    self:UpdateChatChannels()
end

function BossFilter:UpdateChatChannels()
    local list = {GetChannelList()}
    local k = table.getn(channels)
    for i=1,table.getn(list)/2 do
        local skip = false
        for _, v in pairs(channels) do
            -- we don't want to insert channels multiple times
            if (v == list[i*2]) then skip = true break end
        end
        if (not skip) then channels[k+i+1] = list[i*2] end
    end
end

function BossFilter:OnCmd(input)
    if not input or input:trim() == "" then
        InterfaceOptionsFrame_OpenToCategory(BossFilter.optionsFrame)
    else
        -- for later slashcommand additions
        LibStub("AceConfigCmd-3.0").HandleCommand(BossFilter, "BossFilter", "BossFilter", input)
    end
end

function BossFilter:OnLDBClick(button)
	if button == "LeftButton" then		
        BossFilter:getAndPlayRandomSound()
    else
        StaticPopupDialogs["BossFilterSearchDialog"] = {
            text = "Phrase to search for or insert ID to play", 
			button1 = ACCEPT, 
			button2 = CANCEL,
			hasEditBox = true,
			timeout = 30, 
			hideOnEscape = true,
            whileDead = true,
			OnAccept = 	function()
				local phrase = getglobal(this:GetParent():GetName().."EditBox"):GetText()
                --getglobal(this:GetParent():GetName().."EditBox"):AddHistoryLine(phrase)
                if type(tonumber(phrase))=="number" then
                    self:PlayYellByID(tonumber(phrase))
                else
                    self:Search(phrase)
                end
			end,
        }
        StaticPopup_Show("BossFilterSearchDialog")
    end
end

function BossFilter:tablength(tab)
	if(tab == nil) then 
		return 0 
	end
	local n=0
	for _ in pairs(tab) do
		n=n+1
	end
	return n
end

function BossFilter:Debug(text)
    if not self:getDebugMode() then return end
    self:Print(text)
end

function BossFilter:startswith(String,Start)
    return string.sub(String,1,string.len(Start))==Start
end

function BossFilter:getAndPlayRandomSound()
    local rndInstance = random(self:tablength(self.data))
    local i = 0
    for k,_ in pairs(self.data) do
        i = i + 1
        if (i == rndInstance) then rndInstance = k end
    end
    local rndBoss = random(self:tablength(self.data[rndInstance]))
    i = 0
    for k,_ in pairs(self.data[rndInstance]) do
        i = i + 1
        if (i == rndBoss) then rndBoss = k end
    end
    local rndText = random(self:tablength(self.data[rndInstance][rndBoss]))
    local rndSound
    i = 0
    for k, v in pairs(self.data[rndInstance][rndBoss]) do
        i = i + 1
        if (i == rndText) then 
            rndText = k
            rndSound = v
        end
    end
    self:Play(rndInstance, rndBoss, rndText, rndSound)
end

function BossFilter:PlayYellByID(ID)
    if (type(ID) ~= "number") then return end
    local i = 0
    for zone_key, _ in pairs(self.data) do
        for boss_key, _ in pairs(self.data[zone_key]) do
            for yell_key, sound in pairs(self.data[zone_key][boss_key]) do
                i = i + 1
                if(i == ID) then self:Play(zone_key, boss_key, yell_key, sound) return end
            end
        end        
    end
end

function BossFilter:Search(phrase)
	if (type(tonumber(phrase)) ~= "number" and string.len(phrase) < 3) then
		self:Print("|cffff3333".."Please enter 3 or more letters!|r")
		return
	end
	local searchcount = 0
    local i = 0
	DEFAULT_CHAT_FRAME:AddMessage("|cffB954FF".."BossFilter search results for \""..phrase.."\":|r")
    for zone_key, _ in pairs(self.data) do
        for boss_key, _ in pairs(self.data[zone_key]) do
            -- We can also search for a bossname. If it's found we output every yell from this boss
            if string.find(string.lower(boss_key), string.lower(phrase)) ~= nil then
                if (self:tablength(self.data[zone_key][boss_key]) > 0) then  DEFAULT_CHAT_FRAME:AddMessage("|cffff0000"..boss_key.."|r|cffffff00 in "..zone_key..":|r") else break end
                for yell, _ in pairs(self.data[zone_key][boss_key]) do
                    i = i + 1
                    searchcount = searchcount + 1
                    DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00|Hbtplay:"..self.data[zone_key][boss_key][yell].."|h".."[#"..i.."]|h:|r |cffff9911"..yell.."|r|h")
                end
            else     
                for yell, _ in pairs(self.data[zone_key][boss_key]) do
                    i = i + 1
                    if string.find(string.lower(yell), string.lower(phrase)) ~= nil then
                        searchcount = searchcount + 1
                        local a, b = string.find(string.lower(yell), string.lower(phrase))
                        DEFAULT_CHAT_FRAME:AddMessage("|cffffff00"..boss_key.." in "..zone_key..":|r")	 
                        DEFAULT_CHAT_FRAME:AddMessage("|cff00ff00|Hbtplay:"..self.data[zone_key][boss_key][yell].."|h".."[#"..i.."]|h:|r |cffff9911"..string.sub(yell, 1, a-1).."|r|cffff0000"..string.sub(yell, a, b).."|r|cffff9911"..string.sub(yell, b+1).."|r|h")
                    end                
                end
            end

        end
    end
	DEFAULT_CHAT_FRAME:AddMessage("|cffB954FF"..searchcount.." matches.|r")
end

function BossFilter:SetItemRef(link, text, button)
	local linkType = string.sub(link, 1, 6)
	if linkType == "btplay" then
		local sound = string.match(link, "btplay:([^:]+)")
        PlaySoundFile("Sound\\Creature\\"..sound..".wav")
		--self:PlayYellByID(tonumber(id))
		return nil
	end
	return self.hooks.SetItemRef(link, text, button)
end

function BossFilter:Play(instance, boss, text, sound)
	if self:getSound() then 
		PlaySoundFile("Sound\\Creature\\"..sound..".wav")
	end
    if self:getAddOutput() then
        self:Print("Quoted from |cffffff00"..boss.."|r")
        UIErrorsFrame:AddMessage(text, 1.0, 0.2, 0.2, 1, 5);
		DEFAULT_CHAT_FRAME:AddMessage(text, 1.0, 0.2, 0.2, 1, 5);
    end
	if (self:getText() and self:getChannel()~=nil) then
		if self:getChannel() == "EMOTE" then
			SendChatMessage(" quotes "..boss..": \""..text.."\"", channels[self:getChannel()]) 
		else
            if (GetChannelName(self:getChannel()) == nil) then
                SendChatMessage(text, channels[self:getChannel()])
            else
                SendChatMessage(text, "CHANNEL", nil, GetChannelName(channels[self:getChannel()]))
            end
		end
	end
end

function BossFilter:Levenshtein(s, t)
	local d, sn, tn = {}, #s, #t
	local byte, min = string.byte, math.min
	for i = 0, sn do d[i * tn] = i end
	for j = 0, tn do d[j] = j end
	for i = 1, sn do
		local si = byte(s, i)
		for j = 1, tn do
            d[i*tn+j] = min(d[(i-1)*tn+j]+1, d[i*tn+j-1]+1, d[(i-1)*tn+j-1]+(si == byte(t,j) and 0 or 1))
		end
	end
	return d[#d]
end

function BossFilter:CHAT_MSG_MONSTER_SAY(_, yell, boss)
	if (boss==nil or yell==nil) then return end
	self:CHAT_MSG_MONSTER_YELL(nil, yell, boss)
end

function BossFilter:CHAT_MSG_MONSTER_WHISPER(_, yell, boss)
	if (boss==nil or yell==nil) then return	end
	self:CHAT_MSG_MONSTER_YELL(nil, yell, boss)
end

function BossFilter:CHAT_MSG_MONSTER_YELL(_, yell, boss)
	if (boss==nil or yell==nil) then return end
    
    local knownBoss = false
    
    local inInstance, instanceType = IsInInstance()
    local zone = (tostring(GetRealZoneText()) or tostring(GetZoneText()) or tostring(getMinimapZoneText) or "Unknown Zone")
    
    -- we always exit on an invalid zone
    if (not self.data[zone]) then self:Debug("Found an invalid zone : " .. tostring(zone)) return end
    if (self.data[zone][boss]) then knownBoss = true else
        -- We only want to guess names if the option is enabled cause it may decrease performance due to multiple Levenshtein algorithm usage
        if (self:getNameGuess()) then
            local min, minBoss, leven = string.len(boss), nil
            for k, _ in pairs (self.data[zone]) do
                leven = self:Levenshtein(k,boss)
                --self:Debug(k .. " : " .. leven)
                if (leven < min) then 
                    min = leven
                    minBoss = k
                end    
            end
            
            -- just for some testing we pretend to have really found the boss at a given treshold
            if (min < (string.len(boss)/4)) then
                self:Debug("\"".. tostring(boss) .. "\" probably called \"" .. tostring(minBoss) .. "\" in the database please verify")
                self:Debug("Min is: " .. tostring(min) .. " ; string.len(boss) is : " .. tostring(string.len(boss)))
                self:Debug("We'll give ".. tostring(boss) .. " a chance as " .. tostring(minBoss))
                boss = minBoss
                -- lets give this boss a chance
                knownBoss = true
            end
        end
        -- we only investigate the yell again when we're quite sure we've found a matching boss name after all    
        if (knownBoss ~= true) then
            if IsInInstance() then self:Debug("Found an unkown boss : " .. tostring(boss)) end
            return
        end
    end
   
    -- efficiency tweak to not always use the whole table
    local bossTable = self.data[zone][boss]
    -- best possible situation: we've direcly found the yell!
    if (bossTable[yell]) then self:Play(zone, boss, yell, bossTable[yell]) return end

    --Now the guessing fun begins
    --if (string.find(zone, "Ruby Sanctum") ~= nil) then  -- its the new raid.      
        
    -- we dont want to store messages with a player names inside           
    -- I've never seen a yell containing party/raid members' names yet except Bloodlord Mandokir(or can't remind one), so its commented out
    --[[if GetNumRaidMembers() > 0 then
        for i=1,GetNumRaidMembers() do
            if (string.find(yell, (UnitName("raid"..i))) ~= nil) then return self:Debug("Found in Raid!") end                    
        end
    elseif GetNumPartyMembers() > 0 then
        for i=1,GetNumPartyMembers() do
            if (string.find(yell, (UnitName("party"..i))) ~= nil) then return self:Debug("Found in Party!") end
        end
    end]]
    -- it can also be the player (while in a party or when solo)
    if (string.find(yell, (UnitName("player"))) ~= nil) then return --[[self:Debug("Found the player!")]] end
    
    -- store a possible typo for easier yell-fixing
    if self:getDebugMode() then
        local fixme = true
        for i=1,self:tablength(self.db.global.useryell) do
            if type(self.db.global.useryell[i].PossibleTypoOrUnknown) ~= "nil" then
                if self.db.global.useryell[i].PossibleTypoOrUnknown == yell then fixme = false end
            end
        end
        if fixme then self.db.global.useryell[self:tablength(self.db.global.useryell)+1] = {["PossibleTypoOrUnknown"] = yell, ["boss"] = boss} end
    end
    -- maybe the yell is inside one of those strings
    for dbYell, sound in pairs(bossTable) do
        -- if the yell ingame is a prefix of a databased yell and has at least 4 letters we will play it
        if (self:startswith(dbYell, yell) and string.len(yell) > 3) then self:Play(zone, boss, dbYell, sound) return end
        -- if the yell ingame is inside a databased yell and has at least 4 letters (substring with 126 letters due to sucky string.find function) we can ignore it
        if (string.len(yell) > 3 and string.find(dbYell, string.sub(yell, 0, math.min(string.len(yell), 126))) ~= nil) then return end
    end

    -- We already got you as a useryell?
    for i=1,self:tablength(self.db.global.useryell) do
        if type(self.db.global.useryell[i].text) ~= "nil" then
            if self.db.global.useryell[i].text == yell then return end
        end
    end
    
    if (self.db.global.useryell) then self.db.global.useryell[self:tablength(self.db.global.useryell)+1]={["boss"]=boss, ["zone"]=zone, ["text"]=yell} end
    self:Print("New yell collected!")
end

function BossFilter:getText()
    return self.db.global.text
end

function BossFilter:toggleText()
    self.db.global.text = not self.db.global.text
end

function BossFilter:getSound()
    return self.db.global.sound
end

function BossFilter:toggleSound(value)
    self.db.global.sound = not self.db.global.sound
end

function BossFilter:getChannel()
    return self.db.global.channel
end

function BossFilter:setChannel(value)
    self.db.global.channel = value
end

function BossFilter:getAddOutput()
    return self.db.global.addoutput
end

function BossFilter:toggleAddOutput()
    self.db.global.addoutput = not self.db.global.addoutput
end

function BossFilter:getDebugMode()
    return self.db.global.debug
end

function BossFilter:toggleDebugMode()
    self.db.global.debug = not self.db.global.debug
end

function BossFilter:getNameGuess()
    return self.db.global.nameguess
end

function BossFilter:toggleNameGuess()
    self.db.global.nameguess = not self.db.global.nameguess
end
-- 抽車音效。下列 SoundId 都在 Studio Play 用 ContentProvider 預載，IsLoaded 為 true。
-- 來源是 Roblox Creator Store 免費素材：
-- Pro Sound Effects（說明標 Courtesy of Pro Sound Effects）、APM Music（APMOfficial，Courtesy of APM Music）。
-- 沒有使用其他遊戲的官方音效，也沒有用電子提示音改音高冒充傳說旋律。
local GachaSoundConfig = {}

local function cue(soundId: string, volume: number, speed: number, cutoff: number?)
	return table.freeze({
		soundId = soundId,
		volume = volume,
		speed = speed,
		cutoff = cutoff,
	})
end

-- 9125626478 Lever Mechanism Crank Clicks Big Metal Clunk，Pro Sound Effects，實測 1.47 秒。
GachaSoundConfig.start = cue("rbxassetid://9125626478", 0.72, 1.05, 1.05)
-- 9119717523 Switch Click On Or Off Toggle Button 2，Pro Sound Effects，實測 0.23 秒。
-- 這段原檔音量偏低，所以播放音量設高一些，避免喀噠聲被啟動聲蓋掉。
GachaSoundConfig.tick = cue("rbxassetid://9119717523", 1.6, 1, nil)
-- 9116673944 Metal Impact Heavy Clunking Hits Scraping 4，Pro Sound Effects，實測 0.87 秒。
GachaSoundConfig.lock = cue("rbxassetid://9116673944", 0.34, 0.82, 0.95)

local CHIME_A = "rbxassetid://9114132743" -- Door Chime 12，Pro Sound Effects
local CHIME_B = "rbxassetid://9114132738" -- Door Chime 11，Pro Sound Effects
local METAL = "rbxassetid://9116673678" -- Metal Impact Heavy Clunking Hits Scraping 1
local CLUNK = "rbxassetid://9125665716" -- Metal Clunk Moviola Device
local CARTOON = "rbxassetid://1844278029" -- Cartoon Time 3 (b) Link 2，APM Music
local HIT = "rbxassetid://9043151109" -- Get Up And Go - Hit，APM Music

GachaSoundConfig.reveal = table.freeze({
	Common = table.freeze({
		cue(CHIME_A, 0.24, 1, 0.65),
	}),
	Uncommon = table.freeze({
		cue(CHIME_A, 0.22, 1, 0.5),
		cue(CHIME_B, 0.24, 1.12, 0.5),
	}),
	Rare = table.freeze({
		cue(CARTOON, 0.28, 1, 1.35),
	}),
	Epic = table.freeze({
		cue(METAL, 0.3, 0.92, 0.9),
		cue(HIT, 0.26, 1, 1.45),
	}),
	Legendary = table.freeze({
		cue(METAL, 0.36, 0.68, 1.05),
		cue(CLUNK, 0.24, 0.9, 0.75),
	}),
})

-- 完整音檔 13.86 秒。只播開頭 2.6 秒，這段在 Studio 量到持續有聲。
GachaSoundConfig.legendaryMelody = table.freeze({
	soundId = "rbxassetid://83315768373322",
	name = "Conquering Heroes Link",
	volume = 0.3,
	duration = 2.6,
	delay = 1.15,
})

GachaSoundConfig.revealGap = table.freeze({
	Common = 0,
	Uncommon = 0.16,
	Rare = 0,
	Epic = 0.12,
	Legendary = 0.38,
})

return GachaSoundConfig

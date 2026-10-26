-- 抽車音效只用固定數量的 Sound，不會每幀新建。
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local SoundService = game:GetService("SoundService")

local GachaSoundConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GachaSoundConfig"))

local GachaSound = {}

local muted = false
local generation = 0
local group = Instance.new("SoundGroup")
group.Name = "CarForgeTaxGacha"
group.Volume = 1
group.Parent = SoundService

local pool = {}
local melodyVoices = {}

local function makeSound(name: string, soundId: string): Sound
	local sound = Instance.new("Sound")
	sound.Name = name
	sound.SoundId = soundId
	sound.Looped = false
	sound.SoundGroup = group
	sound.Parent = SoundService
	return sound
end

local function voice(name: string, soundId: string): Sound
	local sound = pool[name]
	if sound == nil or sound.Parent == nil then
		sound = makeSound(name, soundId)
		pool[name] = sound
	end
	if sound.SoundId ~= soundId then
		sound.SoundId = soundId
	end
	return sound
end

local function melodyVoice(index: number, soundId: string): Sound
	local sound = melodyVoices[index]
	if sound == nil or sound.Parent == nil then
		sound = makeSound("GachaMelody" .. index, soundId)
		melodyVoices[index] = sound
	end
	return sound
end

function GachaSound.isMuted(): boolean
	return muted
end

function GachaSound.setMuted(nextMuted: boolean)
	muted = nextMuted == true
	group.Volume = if muted then 0 else 1
	if muted then
		GachaSound.stopAll()
	end
end

function GachaSound.stopAll()
	generation += 1
	for _, sound in pairs(pool) do
		sound:Stop()
	end
	for _, sound in ipairs(melodyVoices) do
		sound:Stop()
	end
end

local function playCue(name: string, spec, gen: number)
	if gen ~= generation or muted or spec == nil then
		return
	end
	local sound = voice(name, spec.soundId)
	sound.Volume = spec.volume
	sound.PlaybackSpeed = spec.speed
	sound.TimePosition = 0
	sound:Play()
	local cutoff = spec.cutoff
	if type(cutoff) == "number" and cutoff > 0 then
		task.delay(cutoff, function()
			if gen ~= generation or sound.SoundId ~= spec.soundId then
				return
			end
			sound:Stop()
		end)
	end
end

function GachaSound.playStart()
	local gen = generation
	playCue("start", GachaSoundConfig.start, gen)
end

function GachaSound.playTick()
	if muted then
		return
	end
	local spec = GachaSoundConfig.tick
	local sound = voice("tick", spec.soundId)
	sound.Volume = spec.volume
	sound.PlaybackSpeed = spec.speed
	sound.TimePosition = 0
	sound:Play()
end

function GachaSound.playLock()
	playCue("lock", GachaSoundConfig.lock, generation)
end

function GachaSound.playReveal(qualityId: string)
	local gen = generation
	local notes = GachaSoundConfig.reveal[qualityId]
	if notes == nil then
		return
	end
	local spacing = GachaSoundConfig.revealGap[qualityId] or 0.12
	for index, spec in ipairs(notes) do
		local delay = (index - 1) * spacing
		task.delay(delay, function()
			playCue("reveal" .. index, spec, gen)
		end)
	end
	if qualityId ~= "Legendary" then
		return
	end
	local melody = GachaSoundConfig.legendaryMelody
	task.delay(melody.delay, function()
		if gen ~= generation or muted then
			return
		end
		local sound = melodyVoice(1, melody.soundId)
		sound.Volume = melody.volume
		sound.PlaybackSpeed = 1
		sound.TimePosition = 0
		sound:Play()
		task.delay(melody.duration, function()
			if gen ~= generation or sound.SoundId ~= melody.soundId then
				return
			end
			sound:Stop()
		end)
	end)
end

return GachaSound

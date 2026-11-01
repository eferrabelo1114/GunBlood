--!strict
--[[
	Holds active server announcements (dashboard broadcasts, shutdown notices) in a Charm signal.
	The UI renders NotificationController.Announcements(); each entry expires after its duration.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Charm = require(ReplicatedStorage.Shared.Packages.charm)
local Net = require(ReplicatedStorage.Shared.Modules.Net)

export type Announcement = {
	Id: number,
	Text: string,
}

local MAX_VISIBLE = 3

local getAnnouncements, setAnnouncements = Charm.signal({} :: { Announcement })

local NotificationController = {
	Priority = 50,
	-- Charm getter: currently visible announcements, oldest first.
	Announcements = getAnnouncements,
}

local nextId = 0

function NotificationController:Show(text: string, duration: number)
	nextId += 1
	local id = nextId

	setAnnouncements(function(current)
		local nextList = table.clone(current)
		table.insert(nextList, { Id = id, Text = text })
		while #nextList > MAX_VISIBLE do
			table.remove(nextList, 1)
		end
		return nextList
	end)

	task.delay(duration, function()
		setAnnouncements(function(current)
			local nextList = {}
			for _, announcement in current do
				if announcement.Id ~= id then
					table.insert(nextList, announcement)
				end
			end
			return nextList
		end)
	end)
end

function NotificationController:Init()
	Net.Announcement.listen(function(announcement)
		self:Show(announcement.text, announcement.duration)
	end)
end

return NotificationController

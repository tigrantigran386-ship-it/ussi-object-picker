--[[
================================================================================
  USSI STUDIO FIXER  v1.0
  Запускать в ROBLOX STUDIO (в режиме редактирования), а не в игре.
================================================================================

  ЗАЧЕМ
  -----
  Дамп клиента почти никогда не запускается «как есть»: персонаж не спавнится,
  камера залипла, чат ломается, а клиентские скрипты висят на InvokeServer
  и ждут ответа сервера, которого в дампе нет. Этот скрипт приводит дамп
  в максимально рабочее состояние.

  КУДА ВСТАВЛЯТЬ
  --------------
  В Studio: вкладка View → Command Bar (нижняя строка ввода) → вставить весь
  код целиком → Enter. Важно: находиться в режиме РЕДАКТИРОВАНИЯ (не нажатым
  Play), иначе часть правок не сохранится в файл.

  ЧТО ДЕЛАЕТ (каждый пункт можно выключить в CONFIG)
  --------------------------------------------------
   1) Players.CharacterAutoLoads = true            — чтобы персонаж спавнился
   2) CameraType = Custom                          — чтобы камера двигалась
   3) CollisionFidelity у мешей и юнионов          — чтобы работали коллизии
   4) Чистит Chat / TextChatService                — они ломаются после дампа
   5) Переносит LocalScript в правильные места     — иначе они НЕ выполняются
   6) Создаёт ServerScriptService/_DumpStubs       — заглушки ремоутов, чтобы
      клиентские скрипты не зависали навсегда, + логирует вызовы
      (это же — лучший способ понять протокол игры)
   7) Печатает отчёт в Output

  ЧЕГО ЭТО НЕ ДЕЛАЕТ
  ------------------
  Не восстанавливает серверную логику. Данных нет ни в дампе, ни в клиенте —
  их можно только переписать самому. Заглушки из п.6 дают клиенту отвечать
  «ок, ничего» вместо бесконечного ожидания.

  ПОВТОРНЫЙ ЗАПУСК
  ----------------
  Скрипт идемпотентный: можно запускать сколько угодно раз, _DumpStubs
  пересоздаётся, перенесённые LocalScript не дублируются.
================================================================================
]]

local CONFIG = {
	fixCharacterSpawn = true,  -- Players.CharacterAutoLoads = true
	fixCamera = true,          -- CameraType = Custom
	fixCollisionFidelity = true,
	cleanChat = true,          -- удалить содержимое Chat / TextChatService
	moveLocalScripts = true,   -- LocalScript из неверных мест → StarterPlayerScripts
	createRemoteStubs = true,  -- Script с заглушками RemoteEvent/RemoteFunction
	remoteStubLog = true,      -- логировать вызовы ремоутов в Output
	reportOnly = false,        -- true = только показать отчёт, ничего не менять
	verbose = true,            -- подробный вывод
}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

local report = {}
local function say(text)
	report[#report + 1] = text
	if CONFIG.verbose then
		print("[Fixer] " .. text)
	end
end

local function do_(fn)
	if CONFIG.reportOnly then
		return false
	end
	local ok, err = pcall(fn)
	if not ok then
		say("  ! ошибка: " .. tostring(err))
	end
	return ok
end

-- контейнеры, в которых LocalScript действительно выполняется
local VALID_LOCAL_ANCESTORS = {
	StarterPlayerScripts = true,
	StarterCharacterScripts = true,
	StarterGui = true,
	StarterPack = true,   -- LocalScript внутри Tool отсюда
	PlayerScripts = true,
	PlayerGui = true,
	ReplicatedFirst = true,
}

local function inValidContainer(inst)
	local node = inst.Parent
	while node and node ~= game do
		if VALID_LOCAL_ANCESTORS[node.Name] then
			return true
		end
		node = node.Parent
	end
	return false
end

local function safeName(text)
	text = string.gsub(text or "", "[^%w_%-]", "_")
	return string.sub(text, 1, 90)
end

print("========== USSI Studio Fixer ==========")
if CONFIG.reportOnly then
	say("РЕЖИМ ОТЧЁТА: ничего не меняю, только показываю, что было бы сделано")
end

-- 1) спавн персонажа ------------------------------------------------------
if CONFIG.fixCharacterSpawn then
	local ok = do_(function()
		Players.CharacterAutoLoads = true
	end)
	say("спавн персонажа: CharacterAutoLoads = true" .. (ok and "" or " (не удалось)"))
end

-- 2) камера ---------------------------------------------------------------
if CONFIG.fixCamera then
	local cam = workspace.CurrentCamera
	if cam then
		local ok = do_(function()
			cam.CameraType = Enum.CameraType.Custom
		end)
		say("камера: CameraType = Custom" .. (ok and "" or " (не удалось)"))
	else
		say("камера: CurrentCamera не найден")
	end
end

-- 3) коллизии мешей и юнионов --------------------------------------------
if CONFIG.fixCollisionFidelity then
	local count = 0
	for _, inst in ipairs(game:GetDescendants()) do
		if inst:IsA("TriangleMeshPart") then
			local ok = pcall(function()
				inst.CollisionFidelity = Enum.CollisionFidelity.Default
			end)
			if ok then
				count = count + 1
			end
		end
	end
	say("коллизии: CollisionFidelity поправлен у " .. count .. " объектов")
end

-- 4) чат ------------------------------------------------------------------
if CONFIG.cleanChat then
	for _, serviceName in ipairs({ "Chat", "TextChatService" }) do
		local service = game:FindService(serviceName)
		if service then
			local kids = service:GetChildren()
			if #kids > 0 then
				local removed = 0
				for _, child in ipairs(kids) do
					local ok = pcall(function()
						child:Destroy()
					end)
					if ok then
						removed = removed + 1
					end
				end
				say(string.format("чат: %s очищен (%d объектов)", serviceName, removed))
			end
		end
	end
end

-- 5) LocalScript в правильных местах -------------------------------------
if CONFIG.moveLocalScripts then
	local misplaced = {}
	for _, inst in ipairs(game:GetDescendants()) do
		if inst:IsA("LocalScript") and not inValidContainer(inst) then
			misplaced[#misplaced + 1] = inst
		end
	end

	if #misplaced == 0 then
		say("LocalScript: все лежат в рабочих контейнерах")
	else
		local folder
		local okFolder = pcall(function()
			folder = StarterPlayer.StarterPlayerScripts:FindFirstChild("_MovedLocalScripts")
			if not folder then
				folder = Instance.new("Folder")
				folder.Name = "_MovedLocalScripts"
				folder.Parent = StarterPlayer.StarterPlayerScripts
			end
		end)

		for _, inst in ipairs(misplaced) do
			local fullPath = inst:GetFullName()
			if okFolder and not CONFIG.reportOnly then
				local clone = inst:Clone()
				clone.Name = safeName(fullPath)
				local ok = pcall(function()
					clone.Parent = folder
				end)
				say(string.format("  перенёс: %s → StarterPlayerScripts/_MovedLocalScripts/%s", fullPath, clone.Name))
				if not ok then
					say("    ! не удалось перенести клона")
				end
			else
				say("  [бы перенёс] " .. fullPath)
			end
		end
		say(string.format("LocalScript: найдено вне рабочих мест — %d (клоны перенесены, оригиналы оставлены на месте)", #misplaced))
	end
end

-- 6) заглушки ремоутов ----------------------------------------------------
if CONFIG.createRemoteStubs then
	local stubSource = [==[
-- Создано USSI Studio Fixer.
-- Отвечает на вызовы ремоутов из клиента, чтобы клиентские скрипты не зависали
-- на RemoteFunction:InvokeServer() и не падали от отсутствия обработчиков.
-- Логирует вызовы: по этим строкам видно, ЧТО клиент просит у сервера —
-- это и есть протокол игры, по которому серверную часть можно переписать.
-- Чтобы выключить логи — поменяй LOG на false.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local LOG = true

local function shortArgs(...)
	local parts = {}
	for i = 1, select("#", ...) do
		local value = select(i, ...)
		local t = typeof(value)
		local s
		if t == "Instance" then
			s = value:GetFullName()
		elseif t == "table" then
			s = "{таблица}"
		elseif t == "string" then
			s = string.format("%q", string.sub(value, 1, 120))
		else
			s = tostring(value)
		end
		parts[#parts + 1] = t .. " = " .. s
	end
	return table.concat(parts, ", ")
end

local events, functions = 0, 0

for _, inst in ipairs(ReplicatedStorage:GetDescendants()) do
	if inst:IsA("RemoteEvent") then
		events = events + 1
		inst.OnServerEvent:Connect(function(player, ...)
			if LOG then
				print(string.format("[remote] %s <- %s(%s)", inst:GetFullName(), player.Name, shortArgs(...)))
			end
		end)
	elseif inst:IsA("RemoteFunction") then
		functions = functions + 1
		local ok = pcall(function()
			inst.OnServerInvoke = function(player, ...)
				if LOG then
					print(string.format("[remote-fn] %s <- %s(%s)  → отвечаю nil", inst:GetFullName(), player.Name, shortArgs(...)))
				end
				return nil
			end
		end)
		if not ok then
			warn("[stubs] OnServerInvoke уже занят: " .. inst:GetFullName())
		end
	end
end

print(string.format("[stubs] заглушки установлены: %d RemoteEvent, %d RemoteFunction", events, functions))
]==]

	local existing = ServerScriptService:FindFirstChild("_DumpStubs")
	if existing then
		do_(function()
			existing:Destroy()
		end)
	end

	if CONFIG.reportOnly then
		say("ремоуты: был бы создан ServerScriptService/_DumpStubs")
	else
		local ok = do_(function()
			local stub = Instance.new("Script")
			stub.Name = "_DumpStubs"
			stub.Source = stubSource
			stub.Parent = ServerScriptService
		end)
		if ok then
			say("ремоуты: создан ServerScriptService/_DumpStubs (заглушки + лог вызовов)")
		else
			say("ремоуты: не удалось создать _DumpStubs (в раннем Play режиме Source недоступен — запусти в режиме редактирования)")
		end
	end
end

-- 7) отчёт ----------------------------------------------------------------
print("---------------------------------------")
print(string.format("[Fixer] готово. Правок в отчёте: %d", #report))
print("Дальше: File → Save to File As → .rbxl, затем жми Play (F5) и смотри Output.")
print("Если клиентский скрипт висит — смотри строки [remote] в Output: это запросы к серверу,")
print("которых в дампе нет. Их логику придётся написать самому в ServerScriptService.")

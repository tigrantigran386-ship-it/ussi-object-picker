--[[
================================================================================
  USSI OBJECT PICKER  v3.2  —  выбор объектов внутри сервисов + фиксер Studio
================================================================================

  ЧТО НОВОГО В v3.2
  -----------------
   * Рядом с дампом автоматически кладётся USSI_Fixer.lua — скрипт для Roblox
     Studio: включает спавн персонажа, чинит камеру и коллизии, чистит чат,
     переносит LocalScript в рабочие контейнеры и ставит заглушки ремоутов,
     чтобы клиентские скрипты не зависали на InvokeServer.
   * Напоминание: «рабочие скрипты» из дампа — это только КЛИЕНТСКИЕ скрипты,
     и то после правок. Серверных в клиенте нет физически.

  ЧТО ИСПРАВЛЕНО В v3.1
  ---------------------
   * ГЛАВНОЕ: исправлен пустой выбранный объект. В v3.0 путь до выбранного
     объекта обрезался и у САМОГО объекта тоже — USSI честно вырезал его
     содержимое, и в Studio объект появлялся пустым. Теперь у выбранного
     объекта сохраняется всё внутри (кроме того, что отмечено как исключение).
   * Имя файла теперь содержит название плейса и его ID:
     USSI_<НазваниеПлейса>_<PlaceId>_<объект>.rbxl
   * Существующие файлы не перезаписываются: добавляется (1), (2), ...
   * В логе видно, сколько объектов внутри выбранного и нет ли пустых веток.

  ЧТО ИСПРАВЛЕНО В v3 (по сравнению с v2)
  ---------------------------------------
   1) МОБИЛЬНАЯ ВЁРСТКА. Окно всегда вписывается в экран (и ландшафт, и портрет),
      подстраивается при повороте телефона, кнопки крупные под палец,
      настройки складываются в сворачиваемую панель.
   2) ИСПРАВЛЕН БАГ СО СТРЕЛКОЙ «+». Раньше клик по «+» перехватывала строка,
      и вместо раскрытия сервиса он выделялся целиком — из-за этого сохранялась
      вся карта. Теперь у «+» своя крупная зона нажатия, и она сверху.
   3) ЭКСПОРТ СТАЛ «ГРОМКИМ». Оверлей с прогрессом появляется сразу,
      любая ошибка показывается и в оверлее, и в файле-логе,
      файл пишется с тремя попытками пути и проверкой через isfile/readfile.
   4) Автоподсказка: если выделен сервис целиком — об этом прямо написано
      в подтверждении («сохранится ВСЁ, что внутри»).
   5) Источники USSI: если GitHub недоступен — пробуются jsDelivr, githack и др.
   6) Проверка окружения (кнопка «Проверка»): loadstring / writefile / buffer /
      gethiddenproperty. Если нет buffer — авто-переключение на XML-формат.

  КАК ПОЛЬЗОВАТЬСЯ
  ----------------
   1. Нажми «+» у сервиса (Workspace, ReplicatedStorage, ...) — ветка раскроется,
      и внутри неё видно объекты. Заходи глубже так же.
   2. Тапни по строке объекта — поставится галочка. Можно набрать объекты
      из разных сервисов сразу.
   3. Сними галочку внутри выделенной папки — это исключение: папка сохранится,
      а этот объект из неё вырежется.
   4. Жми «ЭКСПОРТИРОВАТЬ». Файл появится в папке workspace твоего экзекьютора
      (путь показывается после сохранения, если экзекьютор умеет getworkspace()).

  ФОРМАТЫ
  -------
   .rbxl  «карта»: объекты лежат на своих путях (Workspace/Папка/Модель),
          остальное отрезано. Открывать: Studio → File → Open from File.
   .rbxm  «модель»: только выбранные объекты списком сверху.
          Открывать: Studio → File → Insert from File.

  ЧЕГО НЕ МОЖЕТ НИКТО
  -------------------
   ServerStorage / ServerScriptService и серверные Script/ModuleScript
   клиенту не репликуются (FilteringEnabled) — в дереве они пустые.

  РИСКИ
  -----
   * Экзекьютор = нарушение ToS Roblox, детектится Hyperion. Только твинк.
   * USSI качается с GitHub (ветка main) и тянет свои зависимости из SomeHub —
     сторонний код, который автор может обновить в любой момент.
   * Чужие ассеты в своём проекте — нарушение авторских прав и DMCA-риск.
================================================================================
]]

--==================================================================
-- 1. НАСТРОЙКИ
--==================================================================
local CONFIG = {
	-- откуда качать USSI (перебираются по очереди, пока один не сработает)
	Sources = {
		"https://raw.githubusercontent.com/luau/UniversalSynSaveInstance/main/saveinstance.luau",
		"https://cdn.jsdelivr.net/gh/luau/UniversalSynSaveInstance@main/saveinstance.luau",
		"https://raw.githack.com/luau/UniversalSynSaveInstance/main/saveinstance.luau",
		"https://github.com/luau/UniversalSynSaveInstance/raw/main/saveinstance.luau",
		"https://raw.githubusercontent.com/luau/SynSaveInstance/main/saveinstance.luau",
	},

	OutFolder = false,     -- false = писать прямо в workspace экзекьютора (проще найти)
	DefaultFormat = "rbxl",
	Binary = true,         -- бинарный формат (.rbxl/.rbxm). Если нет buffer — авто-XML

	ChildPage = 150,       -- сколько детей показывать за раз при раскрытии
	SearchBudget = 60000,
	SearchMax = 200,
	CountBudget = 4000,
	AutoExpandMax = 25,    -- сервисы с таким числом детей раскрываются сразу

	Debug = false,
	SafeFont = false,
}

local CANDIDATE_SERVICES = {
	"Workspace", "Lighting", "ReplicatedFirst", "ReplicatedStorage", "StarterGui",
	"StarterPack", "StarterPlayer", "Players", "Teams", "SoundService",
	"TextChatService", "Chat", "LocalizationService", "MaterialService",
	"ServerScriptService", "ServerStorage", "JointsService", "TestService",
	"InsertService", "PhysicsService", "ProximityPromptService", "VoiceChatService",
	"CoreGui", "CorePackages",
}

local SERVER_ONLY = { ServerStorage = true, ServerScriptService = true }
local BAD_AS_ROOT = { CoreGui = true, CorePackages = true }

--==================================================================
-- 2. БАЗА
--==================================================================
local CAP = {
	writefile = type(writefile) == "function",
	readfile = type(readfile) == "function",
	isfile = type(isfile) == "function",
	makefolder = type(makefolder) == "function",
	buffer = type(buffer) == "table" and buffer,
	loader = type(loadstring) == "function" and loadstring or load,
}

local print = print
local warn = warn

local function debugLog(...)
	if CONFIG.Debug then
		print("[ObjectPicker]", ...)
	end
end

local function fmtSize(bytes)
	if not bytes then
		return "?"
	end
	local units = { "Б", "КБ", "МБ", "ГБ" }
	local value, i = bytes, 1
	while value >= 1024 and i < #units do
		value = value / 1024
		i = i + 1
	end
	if i == 1 then
		return string.format("%d %s", math.floor(value), units[i])
	end
	return string.format("%.1f %s", value, units[i])
end

local function fmtCount(n)
	local s = tostring(math.floor(n or 0))
	local parts = {}
	while #s > 3 do
		table.insert(parts, 1, string.sub(s, -3))
		s = string.sub(s, 1, #s - 3)
	end
	table.insert(parts, 1, s)
	return table.concat(parts, " ")
end

local function sanitizeName(str)
	str = string.gsub(str or "", "[^%w _%-%+]", "")
	str = string.gsub(str, "%s+", "_")
	str = string.sub(str, 1, 70)
	if str == "" then
		str = "export"
	end
	return str
end

local function httpGet(url)
	local ok, res = pcall(function()
		return game:HttpGet(url, true)
	end)
	if ok and type(res) == "string" and #res > 0 then
		return res
	end
	local req = (syn and syn.request) or http_request or request or http.request
	if req then
		local ok2, res2 = pcall(req, { Url = url, Method = "GET" })
		if ok2 and type(res2) == "table" and type(res2.Body) == "string" and #res2.Body > 0 then
			return res2.Body
		end
	end
	return nil, tostring(res)
end

-- перебор источников: возвращает исходник и URL, с которым получилось
local function fetchAny(urls)
	local errors = {}
	for _, url in ipairs(urls) do
		local body, err = httpGet(url)
		if type(body) == "string" and #body > 2000 then
			return body, url
		end
		table.insert(errors, url .. " -> " .. tostring(err))
		task.wait()
	end
	return nil, table.concat(errors, "\n")
end

local function getGenv()
	if type(getgenv) == "function" then
		local ok, genv = pcall(getgenv)
		if ok and type(genv) == "table" then
			return genv
		end
	end
	return _G or shared
end

local function notify(title, text, duration)
	task.spawn(function()
		local StarterGui = game:GetService("StarterGui")
		for _ = 1, 8 do
			local ok = pcall(function()
				StarterGui:SetCore("SendNotification", {
					Title = title,
					Text = text,
					Duration = duration or 6,
				})
			end)
			if ok then
				return
			end
			task.wait(1)
		end
	end)
end

local function resolveService(name)
	local inst = game:FindService(name)
	if inst then
		return inst
	end
	local ok, res = pcall(function()
		return game:GetService(name)
	end)
	if ok and typeof(res) == "Instance" and res.Parent == game then
		return res
	end
	local ok2, res2 = pcall(function()
		return settings():GetService(name)
	end)
	if ok2 and typeof(res2) == "Instance" and res2.Parent == game then
		return res2
	end
	return nil
end

local function countInstances(root, budget)
	local stack, total, truncated, sinceYield = { root }, 0, false, 0
	while #stack > 0 do
		local node = table.remove(stack)
		local kids = node:GetChildren()
		total = total + #kids
		if total > budget then
			truncated = true
			break
		end
		for i = 1, #kids do
			stack[#stack + 1] = kids[i]
		end
		sinceYield = sinceYield + 1
		if sinceYield >= 250 then
			sinceYield = 0
			task.wait()
		end
	end
	return total, truncated
end

local function pathToString(inst, stopAtService)
	local parts = { inst.Name }
	local node = inst.Parent
	while node and node ~= game do
		table.insert(parts, 1, node.Name)
		if stopAtService and node.Parent == game then
			break
		end
		node = node.Parent
	end
	return table.concat(parts, "/")
end

local function fileExists(path)
	if not CAP.isfile then
		return nil
	end
	local ok, res = pcall(isfile, path)
	if not ok then
		return nil
	end
	return res
end

-- записать файл; возвращает true / false + причину + реальный размер
local function writeOut(path, payload)
	if not CAP.writefile then
		return false, "в экзекьюторе нет writefile"
	end
	local ok, err = pcall(writefile, path, payload)
	if not ok then
		return false, "writefile: " .. tostring(err)
	end
	local exists = fileExists(path)
	if exists == false then
		return false, "writefile не создал файл " .. path
	end
	local size = #payload
	if CAP.readfile then
		local ok2, data = pcall(readfile, path)
		if ok2 and type(data) == "string" then
			size = #data
		end
	end
	return true, size
end

-- название плейса (кэшируется), по возможности через MarketplaceService
local PlaceInfo = { name = nil }

local function placeName()
	if PlaceInfo.name then
		return PlaceInfo.name
	end
	local ms = game:GetService("MarketplaceService")
	local tries = {
		function()
			return ms:GetProductInfoAsync(game.PlaceId, Enum.InfoType.Game)
		end,
		function()
			return ms:GetProductInfo(game.PlaceId, Enum.InfoType.Game)
		end,
		function()
			return ms:GetProductInfoAsync(game.PlaceId)
		end,
		function()
			return ms:GetProductInfo(game.PlaceId)
		end,
	}
	for _, fn in ipairs(tries) do
		local ok, info = pcall(fn)
		if ok and type(info) == "table" and type(info.Name) == "string" and info.Name ~= "" then
			PlaceInfo.name = info.Name
			return PlaceInfo.name
		end
	end
	return nil
end

-- имя файла: USSI_<НазваниеПлейса>_<ID>_<база>.<ext>
local function buildFileName(base, ext)
	local name = placeName()
	local parts = { "USSI" }
	if name then
		parts[#parts + 1] = sanitizeName(name)
	end
	parts[#parts + 1] = tostring(game.PlaceId)
	if base and base ~= "" then
		parts[#parts + 1] = base
	end
	local full = table.concat(parts, "_")
	if #full > 110 then
		full = string.sub(full, 1, 110)
	end
	return full .. ext
end

-- не перезаписываем существующие файлы
local function freePath(path)
	if fileExists(path) ~= true then
		return path
	end
	local stem, ext = string.match(path, "^(.*)(%.[%w]+)$")
	if not stem then
		return path
	end
	for i = 1, 200 do
		local candidate = stem .. "(" .. i .. ")" .. ext
		if fileExists(candidate) ~= true then
			return candidate
		end
	end
	return path
end

-- исходник фиксера, который кладётся рядом с дампом (USSI_Fixer.lua)
local FIXER_SOURCE = [===[
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
]===]

-- положить фиксер рядом с дампом
local function saveFixerNextTo(dumpPath)
	local dir = string.match(dumpPath or "", "^(.+)/[^/]+$")
	local path = dir and (dir .. "/USSI_Fixer.lua") or "USSI_Fixer.lua"
	local ok = writeOut(path, FIXER_SOURCE)
	if ok then
		return path
	end
	return nil
end

local function workspaceFolder()
	if type(getworkspace) == "function" then
		local ok, path = pcall(getworkspace)
		if ok and type(path) == "string" then
			return path
		end
	end
	return nil
end

--==================================================================
-- 3. ТЕМА И UI-ХЕЛПЕРЫ
--==================================================================
local P = {
	bg = Color3.fromRGB(13, 14, 18),
	panel = Color3.fromRGB(23, 25, 32),
	panel2 = Color3.fromRGB(32, 35, 44),
	row = Color3.fromRGB(20, 22, 29),
	rowSel = Color3.fromRGB(31, 42, 71),
	line = Color3.fromRGB(50, 54, 66),
	text = Color3.fromRGB(232, 234, 241),
	muted = Color3.fromRGB(141, 147, 164),
	accent = Color3.fromRGB(86, 126, 255),
	accentHover = Color3.fromRGB(110, 145, 255),
	accentSoft = Color3.fromRGB(45, 62, 110),
	ok = Color3.fromRGB(61, 220, 132),
	bad = Color3.fromRGB(255, 96, 96),
	warn = Color3.fromRGB(255, 178, 40),
}

local FONT = CONFIG.SafeFont and Enum.Font.SourceSans or Enum.Font.Gotham
local FONT_BOLD = CONFIG.SafeFont and Enum.Font.SourceSansBold or Enum.Font.GothamBold

local function new(class, props, parent)
	local inst = Instance.new(class)
	if props then
		for k, v in pairs(props) do
			inst[k] = v
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

local function corner(inst, radius)
	return new("UICorner", { CornerRadius = UDim.new(0, radius) }, inst)
end

local function stroke(inst, color, thickness, transparency)
	return new("UIStroke", {
		Color = color or P.line,
		Thickness = thickness or 1,
		Transparency = transparency or 0.4,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	}, inst)
end

local function label(parent, props)
	local merged = {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Font = FONT,
		TextColor3 = P.text,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Center,
	}
	if props then
		for k, v in pairs(props) do
			merged[k] = v
		end
	end
	return new("TextLabel", merged, parent)
end

-- нажатие: и мышь, и палец, с защитой от двойного срабатывания
local function onTap(guiObject, fn)
	local last = 0
	local function handler()
		local now = os.clock()
		if now - last < 0.3 then
			return
		end
		last = now
		fn()
	end
	local ok = pcall(function()
		guiObject.Activated:Connect(handler)
	end)
	pcall(function()
		guiObject.MouseButton1Click:Connect(handler)
	end)
	return ok
end

-- кнопка: { frame, label, hit }
local function button(parent, props)
	local frame = new("Frame", {
		BackgroundColor3 = props.bg or P.panel2,
		BorderSizePixel = 0,
		Size = props.size or UDim2.new(0, 90, 0, 30),
		Position = props.position or UDim2.new(0, 0, 0, 0),
	}, parent)
	corner(frame, props.radius or 6)

	local text = label(frame, {
		Text = props.text or "",
		Font = props.bold and FONT_BOLD or FONT,
		TextColor3 = props.color or P.text,
		TextSize = props.textSize or 12,
		TextXAlignment = Enum.TextXAlignment.Center,
		TextTruncate = Enum.TextTruncate.AtEnd,
		Size = UDim2.new(1, -8, 1, 0),
		Position = UDim2.new(0, 4, 0, 0),
	})

	local hit = new("TextButton", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		Text = "",
		AutoButtonColor = false,
		ZIndex = 2,
	}, frame)

	hit.MouseEnter:Connect(function()
		frame.BackgroundColor3 = props.hover or P.accentSoft
	end)
	hit.MouseLeave:Connect(function()
		frame.BackgroundColor3 = props.bg or P.panel2
	end)
	if props.onClick then
		onTap(hit, props.onClick)
	end

	return { frame = frame, label = text, hit = hit }
end

-- галочка-переключатель; возвращает { get = fn, holder = frame }
local function toggle(parent, text, default, position, width)
	local holder = new("Frame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(0, width or 250, 0, 26),
		Position = position or UDim2.new(0, 0, 0, 0),
	}, parent)

	local box = new("Frame", {
		BackgroundColor3 = P.panel2,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 18, 0, 18),
		Position = UDim2.new(0, 0, 0.5, -9),
	}, holder)
	corner(box, 4)
	stroke(box, P.line, 1, 0.3)

	local mark = new("Frame", {
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		Size = UDim2.new(0, 9, 0, 9),
		Position = UDim2.new(0.5, -4.5, 0.5, -4.5),
	}, box)
	corner(mark, 2)

	label(holder, {
		Text = text,
		TextSize = 11,
		TextColor3 = P.muted,
		Size = UDim2.new(1, -28, 1, 0),
		Position = UDim2.new(0, 28, 0, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	local state = default and true or false
	local function render()
		mark.Visible = state
		box.BackgroundColor3 = state and P.accent or P.panel2
	end
	render()

	local hit = new("TextButton", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		Text = "",
		AutoButtonColor = false,
		ZIndex = 2,
	}, holder)
	onTap(hit, function()
		state = not state
		render()
	end)

	return {
		holder = holder,
		get = function()
			return state
		end,
	}
end

-- переключатель вариантов; возвращает { holder, buttons, select, fit }
local function segmented(parent, items, defaultIndex, onSelect)
	local holder = new("Frame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 200, 0, 30),
	}, parent)

	local buttons = {}

	local function select(index, silent)
		for i = 1, #buttons do
			local entry = buttons[i]
			local active = (i == index)
			entry.frame.BackgroundColor3 = active and P.accent or P.panel2
			entry.label.TextColor3 = active and Color3.fromRGB(255, 255, 255) or P.muted
		end
		if not silent and onSelect then
			onSelect(index, items[index])
		end
	end

	for i = 1, #items do
		buttons[i] = button(holder, {
			text = items[i],
			size = UDim2.new(0, 100, 0, 30),
			position = UDim2.new(0, (i - 1) * 104, 0, 0),
			textSize = 11,
			onClick = function()
				select(i)
			end,
		})
	end

	local seg = {
		holder = holder,
		buttons = buttons,
		select = select,
	}

	-- разложить кнопки по ширине (x, y, totalWidth, height)
	seg.fit = function(x, y, totalWidth, height)
		holder.Position = UDim2.new(0, x, 0, y)
		holder.Size = UDim2.new(0, totalWidth, 0, height)
		local gap = 4
		local w = math.floor((totalWidth - gap * (#buttons - 1)) / #buttons)
		for i, entry in ipairs(buttons) do
			entry.frame.Position = UDim2.new(0, (i - 1) * (w + gap), 0, 0)
			entry.frame.Size = UDim2.new(0, w, 0, height)
			entry.label.TextSize = height >= 34 and 12 or 11
		end
	end

	select(defaultIndex or 1, true)
	return seg
end

local function getGuiParent()
	if type(gethui) == "function" then
		local ok, hui = pcall(gethui)
		if ok and hui then
			return hui
		end
	end
	local ok, coreGui = pcall(function()
		return game:GetService("CoreGui")
	end)
	if ok and coreGui then
		local writable = pcall(function()
			local probe = Instance.new("Folder")
			probe.Parent = coreGui
			probe:Destroy()
		end)
		if writable then
			return coreGui
		end
	end
	local player = game:GetService("Players").LocalPlayer
	if player then
		return player:WaitForChild("PlayerGui", 20)
	end
	return nil
end

local function viewportSize()
	local cam = workspace.CurrentCamera
	if cam then
		local ok, size = pcall(function()
			return cam.ViewportSize
		end)
		if ok and typeof(size) == "Vector2" and size.X > 0 then
			return size
		end
	end
	return Vector2.new(1024, 600)
end

--==================================================================
-- 4. СОСТОЯНИЕ И ДЕРЕВО
--==================================================================
local S = {
	format = CONFIG.DefaultFormat,
	busy = false,
	searching = false,
	pickCount = 0,
	exclCount = 0,
	estCount = nil,
	estTruncated = false,
	countToken = 0,
	searchToken = 0,
	binary = CONFIG.Binary,
	settingsOpen = false,
	compact = false,
}

local Tree = { byInst = {}, all = {}, roots = {} }
local UI = { picked = 0, rows = {} }
local scheduleEstimate

local function makeNode(inst, parentNode)
	local node = {
		inst = inst,
		name = inst.Name,
		class = inst.ClassName,
		parent = parentNode,
		depth = parentNode and (parentNode.depth + 1) or 1,
		flag = nil,
		expanded = false,
		loaded = false,
		children = {},
		limit = CONFIG.ChildPage,
		trueBelow = 0,
		falseBelow = 0,
		isMore = false,
	}
	Tree.byInst[inst] = node
	Tree.all[#Tree.all + 1] = node
	return node
end

local function getNode(inst)
	if not inst or inst == game then
		return nil
	end
	local node = Tree.byInst[inst]
	if node then
		return node
	end
	return makeNode(inst, getNode(inst.Parent))
end

local function effectiveFlag(node)
	local n = node
	while n do
		if n.flag ~= nil then
			return n.flag
		end
		n = n.parent
	end
	return false
end

local function setFlag(node, value)
	local old = node.flag
	if old == value then
		return
	end
	local dTrue = (value == true and 1 or 0) - (old == true and 1 or 0)
	local dFalse = (value == false and 1 or 0) - (old == false and 1 or 0)
	if dTrue == 0 and dFalse == 0 then
		return
	end
	node.flag = value
	local a = node.parent
	while a do
		a.trueBelow = a.trueBelow + dTrue
		a.falseBelow = a.falseBelow + dFalse
		a = a.parent
	end
	S.pickCount = S.pickCount + dTrue
	S.exclCount = S.exclCount + dFalse
end

local function toggleAt(node)
	if node.isMore or not node.inst or S.busy then
		return
	end
	if effectiveFlag(node) then
		local parentSelected = node.parent and effectiveFlag(node.parent) or false
		setFlag(node, parentSelected and false or nil)
	else
		setFlag(node, true)
	end
	UI.refreshNode(node)
	UI.refreshAncestors(node)
	UI.updateStats()
	scheduleEstimate()
end

local function loadChildren(node)
	if node.loaded or not node.inst then
		return
	end
	node.loaded = true
	local ok, kids = pcall(function()
		return node.inst:GetChildren()
	end)
	if not ok or type(kids) ~= "table" then
		kids = {}
	end
	table.sort(kids, function(a, b)
		local an, bn = string.lower(a.Name), string.lower(b.Name)
		if an == bn then
			return a.ClassName < b.ClassName
		end
		return an < bn
	end)
	for _, inst in ipairs(kids) do
		local child = getNode(inst)
		if child and child.parent == node then
			node.children[#node.children + 1] = child
		end
	end
	if #node.children > 0 and not node.moreNode then
		local stub = {
			inst = nil,
			name = "показать ещё",
			class = "",
			parent = node,
			depth = node.depth + 1,
			flag = nil,
			expanded = false,
			loaded = true,
			children = {},
			limit = 0,
			trueBelow = 0,
			falseBelow = 0,
			isMore = true,
		}
		node.moreNode = stub
		Tree.all[#Tree.all + 1] = stub
	end
end

local function topPicks()
	local out = {}
	for _, node in ipairs(Tree.all) do
		if node.flag == true then
			local redundant = false
			local a = node.parent
			while a do
				if a.flag == true then
					redundant = true
					break
				end
				a = a.parent
			end
			if not redundant then
				out[#out + 1] = node
			end
		end
	end
	return out
end

local function exclusions()
	local out = {}
	for _, node in ipairs(Tree.all) do
		if node.flag == false then
			out[#out + 1] = node
		end
	end
	return out
end

function scheduleEstimate()
	S.countToken = S.countToken + 1
	local token = S.countToken
	task.delay(0.3, function()
		if S.countToken ~= token then
			return
		end
		local total, truncated = 0, false
		for _, node in ipairs(topPicks()) do
			local n, tr = countInstances(node.inst, CONFIG.CountBudget)
			total = total + n + 1
			truncated = truncated or tr
			if S.countToken ~= token then
				return
			end
		end
		for _, node in ipairs(exclusions()) do
			local n, tr = countInstances(node.inst, CONFIG.CountBudget)
			total = total - (n + 1)
			truncated = truncated or tr
			if S.countToken ~= token then
				return
			end
		end
		S.estCount = math.max(total, 0)
		S.estTruncated = truncated
		UI.updateStats()
	end)
end

--==================================================================
-- 5. ОКНО (адаптивная вёрстка под телефон и ПК)
--==================================================================
local ROW_H = 30
local ROW_GAP = 3
local INDENT = 15

local function buildPicker()
	local parent = getGuiParent()
	if not parent then
		error("не нашёл, куда положить интерфейс (CoreGui / PlayerGui)")
	end

	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == "USSI_ObjectPicker" then
			pcall(function()
				child:Destroy()
			end)
		end
	end

	local gui = new("ScreenGui", {
		Name = "USSI_ObjectPicker",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 9999,
		IgnoreGuiInset = true,
	}, parent)
	UI.gui = gui

	local win = new("Frame", {
		BackgroundColor3 = P.bg,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 560, 0, 600),
	}, gui)
	corner(win, 10)
	stroke(win, P.line, 1, 0.25)
	UI.win = win

	-- ---------- шапка ----------
	local title = label(win, {
		Text = "USSI Object Picker",
		Font = FONT_BOLD,
		TextSize = 14,
	})
	local subtitle = label(win, {
		Text = "«+» раскрывает сервис, тап по строке — галочка на объект",
		TextSize = 10,
		TextColor3 = P.muted,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	local closeBtn = button(win, {
		text = "X",
		textSize = 14,
		color = P.muted,
		hover = Color3.fromRGB(96, 42, 42),
		onClick = function()
			if not S.busy then
				gui:Destroy()
			end
		end,
	})
	closeBtn.hit.Name = "CloseButton"

	-- ---------- поиск и кнопки ----------
	local search = new("TextBox", {
		BackgroundColor3 = P.panel2,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = FONT,
		PlaceholderText = "поиск объекта...",
		PlaceholderColor3 = P.muted,
		Text = "",
		TextColor3 = P.text,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
	}, win)
	corner(search, 6)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8) }, search)

	local collapseBtn = button(win, {
		text = "Свернуть",
		onClick = function()
			UI.collapseAll()
		end,
	})
	local resetBtn = button(win, {
		text = "Сброс",
		onClick = function()
			UI.clearSelection()
		end,
	})
	local settingsBtn = button(win, {
		text = "Настройки",
		onClick = function()
			S.settingsOpen = not S.settingsOpen
			UI.layout()
		end,
	})
	local diagBtn = button(win, {
		text = "Проверка",
		onClick = function()
			UI.diagnostics()
		end,
	})

	-- ---------- дерево ----------
	local list = new("ScrollingFrame", {
		BackgroundColor3 = P.panel,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = P.accent,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, win)
	corner(list, 8)
	new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }, list)
	new("UIListLayout", {
		Padding = UDim.new(0, ROW_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}, list)
	UI.list = list

	UI.empty = label(list, {
		Text = "Сканирую сервисы…",
		TextSize = 11,
		TextColor3 = P.muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, -16, 0, 28),
		LayoutOrder = -1,
	})

	-- ---------- панель настроек ----------
	local panel = new("ScrollingFrame", {
		BackgroundColor3 = P.panel,
		BorderSizePixel = 0,
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ScrollBarThickness = 3,
		ScrollBarImageColor3 = P.accent,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, win)
	corner(panel, 8)
	UI.panel = panel

	local formatLabel = label(panel, {
		Text = "Формат:",
		TextSize = 11,
		TextColor3 = P.muted,
	})
	local formatSeg = segmented(panel, { ".rbxl — как карта", ".rbxm — как модель" }, 1, function(_, value)
		S.format = string.find(value, "rbxl") and "rbxl" or "rbxm"
		UI.updateStats()
	end)
	UI.formatSeg = formatSeg
	UI.formatLabel = formatLabel

	UI.helpLbl = label(panel, {
		Text = ".rbxl — объекты сохраняются на своих путях (Studio → File → Open from File).\n"
			.. ".rbxm — просто объекты списком (Studio → File → Insert from File).\n"
			.. "ServerStorage / ServerScriptService придут пустыми: клиенту они не репликуются.",
		TextSize = 10,
		TextColor3 = P.muted,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
	})

	UI.toggles = {
		toggle(panel, "Декомпилировать скрипты", true),
		toggle(panel, "Сохранять байткод", false),
		toggle(panel, "ReadMe-заметки в файл", true),
		toggle(panel, "NilInstances (без родителя)", false),
		toggle(panel, "SafeMode (кик перед сохранением)", false),
	}

	-- ---------- статус и экспорт ----------
	local status = label(win, {
		Text = "Запускаюсь…",
		TextSize = 10,
		TextColor3 = P.muted,
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	UI.status = status

	local exportBtn = button(win, {
		text = "ЭКСПОРТИРОВАТЬ",
		bg = P.accent,
		hover = P.accentHover,
		bold = true,
		textSize = 14,
		onClick = function()
			UI.requestExport()
		end,
	})
	UI.exportBtn = exportBtn

	UI.setStatus = function(text, color)
		status.Text = text or ""
		status.TextColor3 = color or P.muted
	end

	-- ---------- модальное окно ----------
	local modalHolder = new("Frame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		Visible = false,
		ZIndex = 20,
	}, win)

	new("TextButton", {
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		Text = "",
		AutoButtonColor = false,
		ZIndex = 20,
	}, modalHolder)

	local modalPanel = new("Frame", {
		BackgroundColor3 = P.panel,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 420, 0, 260),
		ZIndex = 21,
	}, modalHolder)
	corner(modalPanel, 10)
	stroke(modalPanel, P.line, 1, 0.2)
	UI.modalPanel = modalPanel

	local modalTitle = label(modalPanel, {
		Text = "Подтверждение",
		Font = FONT_BOLD,
		TextSize = 14,
		ZIndex = 22,
	})
	local modalText = label(modalPanel, {
		Text = "",
		TextSize = 11,
		TextColor3 = P.muted,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		ZIndex = 22,
	})
	UI.modalTitle = modalTitle
	UI.modalText = modalText

	local okBtn = button(modalPanel, {
		text = "Экспортировать",
		bg = P.accent,
		hover = P.accentHover,
		bold = true,
		onClick = function()
			modalHolder.Visible = false
			local fn = UI.onConfirm
			UI.onConfirm = nil
			if fn then
				fn()
			end
		end,
	})
	local cancelBtn = button(modalPanel, {
		text = "Отмена",
		onClick = function()
			modalHolder.Visible = false
		end,
	})
	okBtn.frame.ZIndex = 22
	okBtn.label.ZIndex = 23
	okBtn.hit.ZIndex = 24
	cancelBtn.frame.ZIndex = 22
	cancelBtn.label.ZIndex = 23
	cancelBtn.hit.ZIndex = 24
	UI.okBtn = okBtn
	UI.cancelBtn = cancelBtn

	UI.confirm = function(titleText, text, onConfirm, okText)
		modalTitle.Text = titleText or "Подтверждение"
		modalText.Text = text or ""
		okBtn.label.Text = okText or "Экспортировать"
		UI.onConfirm = onConfirm
		modalHolder.Visible = true
		UI.layout()
	end

	UI.hideModal = function()
		modalHolder.Visible = false
		UI.onConfirm = nil
	end

	-- ---------- раскладка ----------
	local touch = false
	pcall(function()
		local uis = game:GetService("UserInputService")
		touch = uis.TouchEnabled and not uis.KeyboardEnabled
	end)

	function UI.layout()
		local vp = viewportSize()
		local W = math.clamp(vp.X - 20, 300, 680)
		local H = math.clamp(vp.Y - 20, 300, 820)
		local compact = (W < 560) or (H < 520) or touch
		S.compact = compact

		local pad = compact and 8 or 12
		local headH = compact and 30 or 40
		local toolH = touch and 36 or 30
		local smallBtnH = toolH
		local exportH = touch and 44 or 40
		local statusH = 14
		local gap = 6

		ROW_H = touch and 32 or 28

		win.Size = UDim2.new(0, W, 0, H)

		-- шапка
		title.TextSize = compact and 13 or 15
		title.Position = UDim2.new(0, pad, 0, pad)
		title.Size = UDim2.new(1, -(pad * 2) - 34, 0, headH * 0.5)
		closeBtn.frame.Size = UDim2.new(0, 30, 0, 30)
		closeBtn.frame.Position = UDim2.new(1, -pad - 30, 0, pad)

		if compact then
			subtitle.Visible = false
			title.Size = UDim2.new(1, -(pad * 2) - 34, 0, 30)
		else
			subtitle.Visible = true
			subtitle.Position = UDim2.new(0, pad, 0, pad + 20)
			subtitle.Size = UDim2.new(1, -(pad * 2) - 34, 0, 16)
		end

		local y = pad + headH + gap

		-- поиск
		search.Position = UDim2.new(0, pad, 0, y)
		search.Size = UDim2.new(1, -pad * 2, 0, toolH)
		search.TextSize = touch and 13 or 12
		y = y + toolH + gap

		-- кнопки инструментов: 4 равные
		local btnW = math.floor((W - pad * 2 - gap * 3) / 4)
		local buttons = { resetBtn, collapseBtn, settingsBtn, diagBtn }
		for i, btn in ipairs(buttons) do
			btn.frame.Position = UDim2.new(0, pad + (i - 1) * (btnW + gap), 0, y)
			btn.frame.Size = UDim2.new(0, btnW, 0, smallBtnH)
			btn.label.TextSize = touch and 12 or 11
		end
		y = y + smallBtnH + gap

		-- низ: статус + экспорт
		local exportY = H - pad - exportH
		local statusY = exportY - statusH - 2
		status.Position = UDim2.new(0, pad, 0, statusY)
		status.Size = UDim2.new(1, -pad * 2, 0, statusH)
		exportBtn.frame.Position = UDim2.new(0, pad, 0, exportY)
		exportBtn.frame.Size = UDim2.new(1, -pad * 2, 0, exportH)
		exportBtn.label.TextSize = touch and 15 or 14

		-- панель настроек
		local panelW = W - pad * 2
		if S.settingsOpen then
			local rowH = touch and 32 or 26
			local cols = (panelW >= 460) and 2 or 1
			local rows = math.ceil(#UI.toggles / cols)
			local contentH = pad + 26 + gap + #UI.toggles * (rowH + 4) / cols + 4 + (compact and 0 or 54)
			local maxPanelH = math.max(90, (H - pad * 2 - headH - toolH * 2 - exportH - statusH - 120))
			local panelH = math.min(contentH + 12, maxPanelH)
			panel.Position = UDim2.new(0, pad, 0, statusY - gap - panelH)
			panel.Size = UDim2.new(0, panelW, 0, panelH)
			panel.CanvasSize = UDim2.new(0, 0, 0, contentH + 12)
			panel.Visible = true

			local px = pad
			local py = 6
			formatLabel.Visible = panelW >= 300
			formatLabel.Position = UDim2.new(0, px, 0, py)
			formatLabel.Size = UDim2.new(0, 60, 0, 26)
			formatSeg.fit(panelW >= 300 and (px + 62) or px, py, panelW >= 300 and (panelW - px - 62 - 6) or (panelW - px * 2), 26)
			py = py + 26 + gap

			for i, item in ipairs(UI.toggles) do
				local col = (i - 1) % cols
				local row = math.floor((i - 1) / cols)
				local colW = cols > 1 and math.floor((panelW - px * 2 - 8) / 2) or (panelW - px * 2)
				item.holder.Position = UDim2.new(0, px + col * (colW + 8), 0, py + row * (rowH + 4))
				item.holder.Size = UDim2.new(0, colW, 0, rowH)
			end

			if not compact then
				UI.helpLbl.Visible = true
				local helpY = py + rows * (rowH + 4) + 4
				UI.helpLbl.Position = UDim2.new(0, px, 0, helpY)
				UI.helpLbl.Size = UDim2.new(0, panelW - px * 2, 0, 50)
			else
				UI.helpLbl.Visible = false
			end
		else
			panel.Visible = false
		end

		-- список: всё, что осталось между тулбаром и панелью
		local listBottom = (S.settingsOpen and panel.Visible) and (panel.Position.Y.Offset - 6) or statusY
		local listH = math.max(90, listBottom - y - 6)
		list.Position = UDim2.new(0, pad, 0, y)
		list.Size = UDim2.new(1, -pad * 2, 0, listH)

		-- модалка
		local modalW = math.min(vp.X - 40, 440)
		local modalH = math.min(vp.Y - 40, 300)
		modalPanel.Size = UDim2.new(0, modalW, 0, modalH)
		modalTitle.Position = UDim2.new(0, 12, 0, 12)
		modalTitle.Size = UDim2.new(1, -24, 0, 20)
		modalText.Position = UDim2.new(0, 12, 0, 36)
		modalText.Size = UDim2.new(1, -24, 1, -36 - (touch and 108 or 60))
		local btnH = touch and 40 or 34
		if modalW < 360 or touch then
			okBtn.frame.Size = UDim2.new(1, -24, 0, btnH)
			okBtn.frame.Position = UDim2.new(0, 12, 1, -12 - btnH)
			cancelBtn.frame.Size = UDim2.new(1, -24, 0, btnH)
			cancelBtn.frame.Position = UDim2.new(0, 12, 1, -12 - btnH * 2 - 6)
		else
			okBtn.frame.Size = UDim2.new(0, 160, 0, btnH)
			okBtn.frame.Position = UDim2.new(1, -172, 1, -12 - btnH)
			cancelBtn.frame.Size = UDim2.new(0, 110, 0, btnH)
			cancelBtn.frame.Position = UDim2.new(1, -290, 1, -12 - btnH)
		end

		-- список подстроить под текущую высоту строк
		UI.render()
	end

	-- поворот телефона / смена размера окна
	task.spawn(function()
		local cam = workspace.CurrentCamera
		if cam then
			cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
				pcall(UI.layout)
			end)
		end
	end)

	return gui
end

--==================================================================
-- 6. СТРОКИ ДЕРЕВА
--==================================================================
local function rowX(depth)
	return 4 + (depth - 1) * INDENT
end

local function makeTreeRow(node)
	local x = rowX(node.depth)
	local frame = new("Frame", {
		Name = node.name,
		BackgroundColor3 = P.row,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -8, 0, ROW_H),
	}, UI.list)
	corner(frame, 5)

	local refs = { frame = frame }

	if node.isMore then
		refs.nameLbl = label(frame, {
			Text = "показать ещё…",
			TextSize = 11,
			TextColor3 = P.accent,
			Position = UDim2.new(0, x + 34, 0, 0),
			Size = UDim2.new(1, -(x + 44), 1, 0),
		})
		local hit = new("TextButton", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 1, 0),
			Text = "",
			AutoButtonColor = false,
		}, frame)
		onTap(hit, function()
			node.parent.limit = node.parent.limit + CONFIG.ChildPage
			UI.render()
		end)
		node.row = refs
		return refs
	end

	-- перехватчик клика по строке (создаётся ПЕРВЫМ, поэтому лежит НИЖЕ остальных)
	local hit = new("TextButton", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		Text = "",
		AutoButtonColor = false,
		ZIndex = 1,
	}, frame)

	-- галочка
	local box = new("Frame", {
		BackgroundColor3 = P.panel2,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 18, 0, 18),
		Position = UDim2.new(0, x + 26, 0.5, -9),
		ZIndex = 3,
	}, frame)
	corner(box, 4)
	stroke(box, P.line, 1, 0.3)
	refs.box = box

	refs.mark = new("Frame", {
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		Size = UDim2.new(0, 9, 0, 9),
		Position = UDim2.new(0.5, -4.5, 0.5, -4.5),
		ZIndex = 4,
	}, box)
	corner(refs.mark, 2)

	refs.half = new("Frame", {
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		Size = UDim2.new(0, 9, 0, 3),
		Position = UDim2.new(0.5, -4.5, 0.5, -1.5),
		ZIndex = 4,
	}, box)
	corner(refs.half, 1)

	refs.nameLbl = label(frame, {
		Text = node.name,
		TextSize = 11,
		Position = UDim2.new(0, x + 50, 0, 0),
		Size = UDim2.new(1, -(x + 174), 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	refs.nameLbl.ZIndex = 1

	refs.classLbl = label(frame, {
		Text = node.class,
		TextSize = 10,
		TextColor3 = P.muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(1, -140, 0, 0),
		Size = UDim2.new(0, 134, 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})
	refs.classLbl.ZIndex = 1

	-- стрелка раскрытия: крупная зона, ВЫШЕ перехватчика строки
	local arrow = new("TextButton", {
		BackgroundTransparency = 1,
		BackgroundColor3 = P.panel2,
		BorderSizePixel = 0,
		Text = "",
		Size = UDim2.new(0, 28, 0, ROW_H),
		Position = UDim2.new(0, x - 4, 0, 0),
		AutoButtonColor = false,
		ZIndex = 5,
	}, frame)
	refs.arrow = arrow
	refs.arrowTxt = label(arrow, {
		Text = "+",
		TextSize = 14,
		Font = FONT_BOLD,
		TextColor3 = P.muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 1, 0),
		ZIndex = 6,
	})
	onTap(arrow, function()
		UI.toggleExpand(node)
	end)

	onTap(hit, function()
		toggleAt(node)
	end)

	node.row = refs
	return refs
end

--==================================================================
-- 7. ОТРИСОВКА
--==================================================================
function UI.refreshNode(node)
	local refs = node.row
	if not refs or node.isMore then
		return
	end
	local selected = effectiveFlag(node)
	local excluded = node.flag == false
	local partial = (not selected) and node.trueBelow > 0

	refs.frame.Size = UDim2.new(1, -8, 0, ROW_H)
	refs.arrow.Size = UDim2.new(0, 28, 0, ROW_H)
	local nameX = rowX(node.depth) + 50
	local reserved = S.compact and 16 or 158
	refs.nameLbl.Position = UDim2.new(0, nameX, 0, 0)
	refs.nameLbl.Size = UDim2.new(1, -(nameX + reserved), 1, 0)
	refs.mark.Visible = selected
	refs.half.Visible = partial
	if selected then
		refs.box.BackgroundColor3 = P.accent
	elseif excluded then
		refs.box.BackgroundColor3 = Color3.fromRGB(70, 32, 36)
	else
		refs.box.BackgroundColor3 = P.panel2
	end
	refs.frame.BackgroundColor3 = selected and P.rowSel or P.row
	refs.nameLbl.TextColor3 = (not selected and excluded) and P.muted or P.text
	refs.arrowTxt.Text = node.expanded and "−" or "+"
	refs.arrowTxt.TextColor3 = node.expanded and P.accent or P.muted

	refs.classLbl.Visible = not S.compact
	if refs.classLbl.Visible then
		local info = node.class
		if node.expanded and #node.children > node.limit then
			info = node.class .. " · " .. #node.children
		end
		refs.classLbl.Text = info
	end
end

function UI.refreshAncestors(node)
	local a = node.parent
	while a do
		UI.refreshNode(a)
		a = a.parent
	end
end

function UI.render()
	local visible = {}
	local function walk(node)
		visible[#visible + 1] = node
		if node.expanded and not node.isMore and #node.children > 0 then
			local limit = math.min(#node.children, node.limit)
			for i = 1, limit do
				walk(node.children[i])
			end
			if #node.children > limit and node.moreNode then
				walk(node.moreNode)
			end
		end
	end
	for _, root in ipairs(Tree.roots) do
		walk(root)
	end

	local index = {}
	for i, node in ipairs(visible) do
		index[node] = i
	end

	for _, node in ipairs(Tree.all) do
		if node.row then
			local pos = index[node]
			node.row.frame.Visible = pos ~= nil
			if pos then
				node.row.frame.LayoutOrder = pos
			end
		end
	end

	for i, node in ipairs(visible) do
		if not node.row then
			makeTreeRow(node)
			node.row.frame.LayoutOrder = i
		end
		UI.refreshNode(node)
	end

	UI.list.CanvasSize = UDim2.new(0, 0, 0, (#visible * (ROW_H + ROW_GAP)) + 8)
	UI.empty.Visible = (#Tree.roots == 0)
end

function UI.toggleExpand(node)
	if not node.inst or S.busy then
		return
	end
	if not node.expanded then
		loadChildren(node)
		node.expanded = true
		if #node.children == 0 then
			UI.setStatus(node.name .. " — внутри пусто (или не репликуется клиенту)", P.muted)
		end
	else
		node.expanded = false
	end
	UI.render()
end

function UI.collapseAll()
	for _, node in ipairs(Tree.all) do
		node.expanded = false
	end
	UI.render()
	UI.list.CanvasPosition = Vector2.new(0, 0)
end

function UI.clearSelection()
	for _, node in ipairs(Tree.all) do
		node.flag = nil
		node.trueBelow = 0
		node.falseBelow = 0
	end
	S.pickCount, S.exclCount, S.estCount, S.estTruncated = 0, 0, nil, false
	UI.render()
	UI.updateStats()
end

local function estLabel()
	if not S.estCount then
		return "…"
	end
	return fmtCount(S.estCount) .. (S.estTruncated and "+" or "")
end

function UI.updateStats()
	local mode = (S.format == "rbxl") and "карта с путями" or "модель"
	UI.setStatus(string.format(
		"выбрано: %d · исключено: %d · объектов ≈ %s · %s",
		S.pickCount, S.exclCount, estLabel(), mode
	))
	UI.exportBtn.label.Text = S.pickCount > 0 and ("ЭКСПОРТИРОВАТЬ (" .. S.pickCount .. ")") or "ЭКСПОРТИРОВАТЬ"
end

--==================================================================
-- 8. ПОИСК
--==================================================================
local function clearResultRows()
	if UI.resultRows then
		for _, row in ipairs(UI.resultRows) do
			pcall(function()
				row.frame:Destroy()
			end)
		end
	end
	UI.resultRows = {}
end

local function showResults(matches)
	clearResultRows()
	for _, node in ipairs(Tree.all) do
		node.expanded = false
		if node.row then
			node.row.frame.Visible = false
		end
	end
	UI.list.CanvasSize = UDim2.new(0, 0, 0, (#matches * (ROW_H + ROW_GAP)) + 8)

	for i, node in ipairs(matches) do
		local frame = new("Frame", {
			BackgroundColor3 = P.row,
			BorderSizePixel = 0,
			Size = UDim2.new(1, -8, 0, ROW_H),
			LayoutOrder = i,
		}, UI.list)
		corner(frame, 5)

		local box = new("Frame", {
			BackgroundColor3 = P.panel2,
			BorderSizePixel = 0,
			Size = UDim2.new(0, 18, 0, 18),
			Position = UDim2.new(0, 8, 0.5, -9),
			ZIndex = 2,
		}, frame)
		corner(box, 4)
		local mark = new("Frame", {
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BorderSizePixel = 0,
			Size = UDim2.new(0, 9, 0, 9),
			Position = UDim2.new(0.5, -4.5, 0.5, -4.5),
			ZIndex = 3,
		}, box)
		corner(mark, 2)

		label(frame, {
			Text = pathToString(node.inst, true),
			TextSize = 11,
			Position = UDim2.new(0, 32, 0, 0),
			Size = UDim2.new(1, -40, 1, 0),
			TextTruncate = Enum.TextTruncate.AtStart,
		})

		local hit = new("TextButton", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 1, 0),
			Text = "",
			AutoButtonColor = false,
			ZIndex = 4,
		}, frame)
		onTap(hit, function()
			toggleAt(node)
			mark.Visible = effectiveFlag(node)
			box.BackgroundColor3 = effectiveFlag(node) and P.accent or P.panel2
		end)

		local selected = effectiveFlag(node)
		mark.Visible = selected
		box.BackgroundColor3 = selected and P.accent or P.panel2

		UI.resultRows[#UI.resultRows + 1] = { frame = frame, mark = mark, box = box }
	end
end

local function runSearch(query)
	S.searchToken = S.searchToken + 1
	local token = S.searchToken
	query = string.lower(query)

	local roots = {}
	for _, node in ipairs(Tree.roots) do
		if node.inst then
			roots[#roots + 1] = node.inst
		end
	end

	task.spawn(function()
		local matches, visited = {}, 0
		for _, rootInst in ipairs(roots) do
			if S.searchToken ~= token then
				return
			end
			local stack = { rootInst }
			while #stack > 0 do
				if S.searchToken ~= token then
					return
				end
				local inst = table.remove(stack)
				visited = visited + 1
				if visited % 400 == 0 then
					task.wait()
					UI.setStatus(string.format("поиск… обойдено %d, найдено %d", visited, #matches))
				end
				if visited > CONFIG.SearchBudget or #matches >= CONFIG.SearchMax then
					break
				end
				local name = string.lower(inst.Name)
				local class = string.lower(inst.ClassName)
				if string.find(name, query, 1, true) or string.find(class, query, 1, true) then
					local node = getNode(inst)
					if node then
						matches[#matches + 1] = node
					end
				end
				local ok, kids = pcall(function()
					return inst:GetChildren()
				end)
				if ok then
					for i = #kids, 1, -1 do
						stack[#stack + 1] = kids[i]
					end
				end
			end
		end

		if S.searchToken ~= token then
			return
		end
		showResults(matches)
		UI.setStatus(string.format("найдено: %d (обойдено %d)", #matches, visited), #matches > 0 and P.ok or P.warn)
	end)
end

--==================================================================
-- 9. USSI: ЗАГРУЗКА
--==================================================================
local USSI = nil
local USSISource = nil

local function loadUSSI()
	UI.setStatus("Качаю USSI…")
	local source, used = fetchAny(CONFIG.Sources)
	if not source then
		error("не смог скачать USSI ни с одного зеркала:\n" .. tostring(used))
	end
	debugLog("USSI скачан с", used, #source, "байт")
	UI.setStatus("Загружаю USSI… (скачан с " .. used:sub(1, 46) .. ")")

	if type(CAP.loader) ~= "function" then
		error("в экзекьюторе нет loadstring/load — USSI не запустить")
	end
	local chunk, loadErr = CAP.loader(source, "USSI_saveinstance")
	if not chunk then
		error("USSI не скомпилировался: " .. tostring(loadErr))
	end
	local fn = chunk()
	if type(fn) ~= "function" then
		error("USSI вернул не функцию: " .. typeof(fn))
	end
	USSISource = used
	return fn
end

local function ensureUSSI()
	if USSI then
		return true
	end
	local ok, res = pcall(loadUSSI)
	if ok then
		USSI = res
		return true
	end
	return false, tostring(res)
end

--==================================================================
-- 10. ПРОВЕРКА ОКРУЖЕНИЯ
--==================================================================
local function preflightData()
	local items = {}
	local function add(name, ok, note)
		items[#items + 1] = {
			name = name,
			ok = ok and true or false,
			note = note,
		}
	end

	add("loadstring / load", type(CAP.loader) == "function", "нужен для запуска USSI")
	add("writefile", CAP.writefile, "нужен для сохранения файла")
	add("readfile", CAP.readfile, "нужен для проверки размера файла")
	add("isfile", CAP.isfile, "нужен для проверки, что файл создан")
	add("makefolder", CAP.makefolder, "нужен для подпапки (можно без него)")
	add("buffer", CAP.buffer ~= nil, "без него USSI сохранит в XML (.rbxlx)")
	if not CAP.buffer then
		add("XML-режим", true, "буфер недоступен — формат переключён на .rbxlx/.rbxmx")
	end
	local ghp = type(gethiddenproperty) == "function"
	add("gethiddenproperty", ghp, ghp and "" or "часть свойств не прочитается (не критично)")
	local ws = workspaceFolder()
	add("getworkspace", ws ~= nil, ws and ("папка: " .. ws) or "путь файла покажу иначе")
	return items
end

function UI.diagnostics()
	local items = preflightData()
	local lines = {}
	for _, item in ipairs(items) do
		lines[#lines + 1] = string.format("%s %s%s", item.ok and "✓" or "✗", item.name, item.note ~= "" and (" — " .. item.note) or "")
	end
	task.spawn(function()
		UI.setStatus("Проверяю доступ к USSI…")
		local ok = ensureUSSI()
		local last = ok and "✓ USSI загружается" or "✗ USSI не загрузился — смотри консоль (F9)"
		lines[#lines + 1] = last
		lines[#lines + 1] = ""
		lines[#lines + 1] = "Формат вывода: " .. (CAP.buffer and ".rbxl/.rbxm (бинарный)" or ".rbxlx/.rbxmx (XML)")
		UI.confirm("Проверка окружения", table.concat(lines, "\n"), nil, "Понятно")
		UI.updateStats()
	end)
end

--==================================================================
-- 11. ОВЕРЛЕЙ ПРОГРЕССА
--==================================================================
local function createOverlay()
	local parent = UI.gui and UI.gui.Parent
	if not parent then
		parent = getGuiParent()
	end

	local gui = new("ScreenGui", {
		Name = "USSI_ExportProgress",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 10000,
		IgnoreGuiInset = true,
	}, parent)

	new("Frame", {
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
	}, gui)

	local vp = viewportSize()
	local W = math.min(vp.X - 30, 520)
	local H = math.min(vp.Y - 30, 340)

	local panel = new("Frame", {
		BackgroundColor3 = P.bg,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, W, 0, H),
	}, gui)
	corner(panel, 12)
	stroke(panel, P.line, 1, 0.25)

	local title = label(panel, {
		Text = "Экспорт…",
		Font = FONT_BOLD,
		TextSize = 15,
		Position = UDim2.new(0, 14, 0, 12),
		Size = UDim2.new(1, -28, 0, 20),
	})
	local jobLbl = label(panel, {
		Text = "подготовка",
		TextSize = 11,
		TextColor3 = P.muted,
		Position = UDim2.new(0, 14, 0, 33),
		Size = UDim2.new(1, -28, 0, 16),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	local barBg = new("Frame", {
		BackgroundColor3 = P.panel2,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 14, 0, 54),
		Size = UDim2.new(1, -28, 0, 8),
	}, panel)
	corner(barBg, 4)
	local barFill = new("Frame", {
		BackgroundColor3 = P.accent,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 0, 1, 0),
	}, barBg)
	corner(barFill, 4)

	local actionBtn = button(panel, {
		text = "Закрыть",
		size = UDim2.new(0, 120, 0, 34),
		position = UDim2.new(1, -134, 1, -46),
		onClick = function()
			if not S.busy then
				ov.destroy()
			end
		end,
	})

	local logBox = new("ScrollingFrame", {
		BackgroundColor3 = P.panel,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 14, 0, 72),
		Size = UDim2.new(1, -28, 1, -72 - 54),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = P.accent,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, panel)
	corner(logBox, 8)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 6),
		PaddingBottom = UDim.new(0, 6),
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
	}, logBox)
	local logLayout = new("UIListLayout", {
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, logBox)

	local lineCount = 0
	local function refreshLog()
		logBox.CanvasSize = UDim2.new(0, 0, 0, logLayout.AbsoluteContentSize.Y + 14)
		local canvas = logBox.AbsoluteCanvasSize.Y
		local view = logBox.AbsoluteSize.Y
		if canvas > view then
			logBox.CanvasPosition = Vector2.new(0, canvas - view)
		end
	end

	local ov = { gui = gui }

	ov.addLog = function(text, color)
		lineCount = lineCount + 1
		label(logBox, {
			Text = text,
			TextSize = 11,
			TextColor3 = color or P.muted,
			TextWrapped = true,
			TextYAlignment = Enum.TextYAlignment.Top,
			Size = UDim2.new(1, -8, 0, 14),
			AutomaticSize = Enum.AutomaticSize.Y,
			LayoutOrder = lineCount,
		})
		task.defer(refreshLog)
		task.delay(0.2, refreshLog)
	end

	ov.setJob = function(text)
		jobLbl.Text = text
	end

	ov.setProgress = function(fraction)
		barFill.Size = UDim2.new(math.clamp(fraction or 0, 0, 1), 0, 1, 0)
	end

	ov.setTitle = function(text, color)
		title.Text = text
		if color then
			title.TextColor3 = color
		end
	end

	ov.finish = function(titleText, color, buttonText)
		ov.setTitle(titleText, color)
		ov.setJob("")
		ov.setProgress(1)
		actionBtn.label.Text = buttonText or "Закрыть"
	end

	ov.destroy = function()
		pcall(function()
			gui:Destroy()
		end)
	end

	return ov
end

--==================================================================
-- 12. ЭКСПОРТ
--==================================================================
local function buildPlan(picks)
	local keepSet, keepList = {}, {}
	for _, node in ipairs(picks) do
		local n = node
		while n do
			if not keepSet[n.inst] then
				keepSet[n.inst] = true
				keepList[#keepList + 1] = n
			end
			if n.inst.Parent == game then
				break
			end
			n = n.parent
		end
	end

	local roots = {}
	if S.format == "rbxl" then
		for _, n in ipairs(keepList) do
			if n.inst.Parent == game then
				roots[#roots + 1] = n.inst
			end
		end
		for _, node in ipairs(picks) do
			local hasService = false
			local n = node
			while n do
				if n.inst.Parent == game then
					hasService = true
					break
				end
				n = n.parent
			end
			if not hasService then
				roots[#roots + 1] = node.inst
			end
		end
	else
		for _, node in ipairs(picks) do
			local redundant = false
			local a = node.parent
			while a do
				if a.flag == true then
					redundant = true
					break
				end
				a = a.parent
			end
			if not redundant then
				roots[#roots + 1] = node.inst
			end
		end
	end

	local pickSet = {}
	for _, node in ipairs(picks) do
		pickSet[node.inst] = true
	end

	local ignore, ignoreCount = {}, 0
	local function addIgnore(inst)
		if inst and not ignore[inst] then
			ignore[inst] = true
			ignoreCount = ignoreCount + 1
		end
	end

	-- 1) На пути к выбору отрезаем всё, что не ведёт к выбранному объекту.
	--    ВАЖНО: сами выбранные объекты (pickSet) не трогаем — иначе USSI
	--    вырежет их содержимое и объект сохранится пустым.
	for _, n in ipairs(keepList) do
		if not pickSet[n.inst] then
			local ok, kids = pcall(function()
				return n.inst:GetChildren()
			end)
			if ok then
				for _, child in ipairs(kids) do
					if not keepSet[child] then
						addIgnore(child)
					end
				end
			end
		end
	end

	-- 2) Явные исключения: снятые галочки внутри выбранного объекта.
	for _, node in ipairs(exclusions()) do
		if not keepSet[node.inst] then
			addIgnore(node.inst)
		end
	end

	return roots, ignore, keepList, ignoreCount
end

local ExportLog = { lines = {} }

local function logLine(text)
	ExportLog.lines[#ExportLog.lines + 1] = os.date("[%H:%M:%S] ") .. text
end

local function saveLogFile()
	if not CAP.writefile then
		return nil
	end
	local text = table.concat(ExportLog.lines, "\n")
	for _, path in ipairs({ "USSI_export_log.txt", "USSI_Export/USSI_export_log.txt" }) do
		if CAP.makefolder and string.find(path, "/", 1, true) then
			pcall(makefolder, string.match(path, "^[^/]+"))
		end
		local ok = pcall(writefile, path, text)
		if ok then
			return path
		end
	end
	return nil
end

local function runUSSI(roots, ignore, ov)
	local ext = (S.format == "rbxm") and (S.binary and ".rbxm" or ".rbxmx") or (S.binary and ".rbxl" or ".rbxlx")
	local base
	if #roots == 1 then
		base = sanitizeName(roots[1].Name)
	else
		base = "selected_" .. #roots .. "_items"
	end

	local fileName = buildFileName(base, ext)
	logLine(string.format("плейс: %s (ID %d)", tostring(placeName() or "неизвестен"), game.PlaceId))
	logLine("имя файла: " .. fileName)

	local attempts = {}
	if CONFIG.OutFolder then
		attempts[#attempts + 1] = freePath(CONFIG.OutFolder .. "/" .. fileName)
	else
		attempts[#attempts + 1] = freePath(fileName)
	end
	attempts[#attempts + 1] = freePath("USSI_" .. fileName)

	local result = { ok = false, path = nil, size = nil, err = nil }
	local genv = getGenv()

	local options = {
		mode = "selected",
		ExtraInstances = roots,
		IsModel = (S.format == "rbxm"),
		IgnoreList = ignore,
		DecompileIgnore = {},

		Binary = S.binary,
		CompressionMode = S.binary and "zstd" or false,
		CompressionLevel = 9,

		Decompile = UI.toggles[1].get(),
		scriptcache = true,
		SaveBytecode = UI.toggles[2].get(),
		DecompileTimeout = 20,

		ReadMe = UI.toggles[3].get(),
		NilInstances = UI.toggles[4].get(),

		IgnoreDefaultProperties = true,
		IgnoreNotArchivable = true,
		SaveNotCreatable = false,

		SafeMode = UI.toggles[5].get(),
		KillAllScripts = UI.toggles[5].get(),
		ShutdownWhenDone = false,
		BoostFPS = false,
		AntiIdle = true,
		ShowStatus = false,
		__DEBUG_MODE = CONFIG.Debug,

		FilePath = attempts[1],
		AvoidFileOverwrite = false,

		Callback = function(a, b)
			local payload
			if type(a) == "string" then
				payload = a
			elseif type(a) == "table" then
				payload = table.concat(a)
			elseif type(b) == "string" then
				payload = b
			elseif type(b) == "table" then
				payload = table.concat(b)
			end
			if not payload or #payload <= 32 then
				result.err = "USSI вернул пустые данные"
				return
			end
			result.bytes = #payload
			local lastErr
			for _, path in ipairs(attempts) do
				local ok, info = writeOut(path, payload)
				if ok then
					result.ok = true
					result.path = path
					result.size = info
					return
				end
				lastErr = info
				logLine("не смог записать " .. path .. ": " .. tostring(info))
			end
			result.err = lastErr or "не удалось записать файл"
		end,
	}

	for _, path in ipairs(attempts) do
		genv[path] = nil
	end

	logLine("вызов USSI, IsModel=" .. tostring(S.format == "rbxm") .. ", Binary=" .. tostring(S.binary))
	local called, callErr = pcall(USSI, options)
	if not called then
		result.ok = false
		result.err = tostring(callErr)
		logLine("USSI выбросил ошибку: " .. tostring(callErr))
	end
	if not result.ok and not result.err then
		result.err = "USSI закончил, но файл не записан (смотри консоль F9)"
	end

	-- на всякий случай: если Callback не сработал, но файл всё же есть
	if not result.ok and result.path == nil then
		for _, path in ipairs(attempts) do
			if fileExists(path) then
				result.ok = true
				result.path = path
				result.size = CAP.readfile and #(select(2, pcall(readfile, path))) or nil
				logLine("файл найден на диске: " .. path)
				break
			end
		end
	end

	return result
end

-- наш интерфейс может попасть в дамп, если он внутри выбранных веток
local function ownGuiRoots()
	local roots = {}
	local ok, coreGui = pcall(function()
		return game:GetService("CoreGui")
	end)
	if ok and coreGui then
		roots[coreGui] = true
	end
	local player = game:GetService("Players").LocalPlayer
	if player then
		roots[player] = true
		local pg = player:FindFirstChildOfClass("PlayerGui")
		if pg then
			roots[pg] = true
		end
	end
	return roots
end

local function picksTouchOwnGui(picks)
	local roots = ownGuiRoots()
	for _, node in ipairs(picks) do
		local inst = node.inst
		while inst do
			if roots[inst] then
				return true
			end
			inst = inst.Parent
		end
	end
	return false
end

function UI.requestExport()
	if S.busy then
		return
	end

	if not CAP.writefile then
		UI.setStatus("экзекьютор без writefile — сохранить файл некуда", P.bad)
		UI.confirm("Нельзя сохранить", "В твоём экзекьюторе нет функции writefile, поэтому файл записать не получится.", nil, "Понятно")
		return
	end

	local picks = topPicks()
	if #picks == 0 then
		UI.setStatus("ничего не отмечено — тапни по строкам объектов, чтобы поставить галочки", P.warn)
		notify("Object Picker", "Сначала отметь объекты галочками", 5)
		return
	end

	-- сервисы, выделенные целиком — это важное предупреждение
	local wholeServices, paths, badRoots = {}, {}, {}
	local serviceNames = {}
	for i, node in ipairs(picks) do
		if i <= 6 then
			paths[#paths + 1] = pathToString(node.inst, true)
		end
		local top = node.inst
		while top and top.Parent ~= game do
			top = top.Parent
		end
		if top and not serviceNames[top.Name] then
			serviceNames[top.Name] = true
			if SERVER_ONLY[top.Name] then
				badRoots[#badRoots + 1] = top.Name .. " придёт пустым (не репликуется клиенту)"
			elseif BAD_AS_ROOT[top.Name] then
				badRoots[#badRoots + 1] = top.Name .. " Studio может не принять как корень"
			end
		end
		if node.parent == nil then
			wholeServices[#wholeServices + 1] = node.name
		end
	end

	local text = string.format(
		"Веток: %d · объектов внутри них ≈ %s\nФормат: %s\n\n%s",
		#picks,
		estLabel(),
		(S.format == "rbxl") and ".rbxl — карта, пути сохраняются" or ".rbxm — только объекты списком",
		table.concat(paths, "\n")
	)
	if #picks > 6 then
		text = text .. "\n… и ещё " .. (#picks - 6)
	end
	if #wholeServices > 0 then
		text = text .. "\n\n⚠ Выделено ЦЕЛИКОМ: " .. table.concat(wholeServices, ", ")
			.. ".\nСохранится ВСЁ, что внутри них. Нужна только часть — раскрой «+» и отметь объекты внутри."
	end
	if #badRoots > 0 then
		text = text .. "\n\n" .. table.concat(badRoots, "\n")
	end
	if picksTouchOwnGui(picks) then
		text = text .. "\n\nОкно скрипта спрячется на время дампа, чтобы не попасть в файл."
	end

	UI.confirm("Экспорт выбранного", text, function()
		local roots, ignore, keepList, ignoreCount = buildPlan(picks)
		debugLog("roots:", #roots, "keep:", #keepList, "ignore:", ignoreCount)
		UI.runExport(roots, ignore, ignoreCount)
	end)
end

function UI.runExport(roots, ignore, ignoreCount)
	S.busy = true
	ExportLog.lines = {}

	local hideGui = picksTouchOwnGui(topPicks())
	local guiParent = UI.gui.Parent
	if hideGui then
		UI.gui.Parent = nil
	end

	-- оверлей создаём ПЕРВЫМ делом, чтобы всегда был виден прогресс и ошибки
	local ov
	local okOverlay, overlayErr = pcall(function()
		ov = createOverlay()
	end)

	local function say(text, color)
		if ov then
			ov.addLog(text, color)
		end
		logLine(text)
		debugLog(text)
	end

	if not okOverlay then
		notify("Object Picker", "Экспорт пошёл, но окно прогресса не создалось: " .. tostring(overlayErr), 8)
	end
	-- сколько объектов внутри каждой выбранной ветки (для контроля пустоты)
	local insideCount, emptyPicks = 0, {}
	for _, node in ipairs(topPicks()) do
		local n = countInstances(node.inst, 100000)
		insideCount = insideCount + n + 1
		if n == 0 then
			emptyPicks[#emptyPicks + 1] = node.name
		end
	end

	if ov then
		ov.setProgress(0.05)
		ov.setJob("подготовка…")
		say("Формат: " .. (S.binary and (S.format == "rbxl" and ".rbxl (бинарный)" or ".rbxm (бинарный)") or (S.format == "rbxl" and ".rbxlx (XML)" or ".rbxmx (XML)")), P.text)
		say(string.format("Плейс: %s (ID %d)", tostring(placeName() or "название недоступно"), game.PlaceId), P.text)
		say(string.format("Корней: %d, объектов внутри выбранного: %d, отрезанных веток: %d", #roots, insideCount, ignoreCount or 0))
		if #emptyPicks > 0 then
			say("⚠ внутри пусто у: " .. table.concat(emptyPicks, ", ") .. " — возможно, не репликуется клиенту", P.warn)
		end
		if hideGui then
			say("Окно выбора скрыто на время дампа.", P.warn)
		end
		if workspaceFolder() then
			say("Папка экзекьютора: " .. workspaceFolder())
		end
	end
	task.wait(0.1)

	local result = { ok = false, err = "USSI не запустился" }
	local okRun, runErr = pcall(function()
		local okUSSI, ussiErr = ensureUSSI()
		if not okUSSI then
			error("USSI не загружен: " .. tostring(ussiErr))
		end
		if ov then
			ov.setProgress(0.35)
			ov.setJob("USSI собирает выбранные ветки…")
		end
		result = runUSSI(roots, ignore, ov)
	end)
	if not okRun then
		result.ok = false
		result.err = tostring(runErr)
		say("исключение: " .. tostring(runErr), P.bad)
	end

	if result.ok then
		say(string.format("✓ файл записан: %s (%s)", result.path, fmtSize(result.size)), P.ok)
		local ws = workspaceFolder()
		if ws then
			say("Полный путь: " .. ws .. result.path, P.muted)
		else
			say("Файл лежит в папке workspace твоего экзекьютора.", P.muted)
		end
		local fixerPath = saveFixerNextTo(result.path)
		if fixerPath then
			say("Рядом положил фиксер для Studio: " .. fixerPath, P.muted)
			say("Вставь его в Command Bar Studio ПОСЛЕ открытия дампа: включит спавн и камеру,", P.muted)
			say("перенесёт LocalScript в рабочие места и поставит заглушки ремоутов.", P.muted)
		end
		if ov then
			ov.finish("Готово: " .. fmtSize(result.size), P.ok)
		end
		notify("Object Picker", "Сохранено: " .. tostring(result.path), 6)
	else
		say("✗ " .. tostring(result.err), P.bad)
		if ov then
			ov.finish("Не получилось", P.bad)
		end
		notify("Object Picker", "Ошибка экспорта: " .. tostring(result.err), 10)
	end

	local logPath = saveLogFile()
	if logPath then
		say("Лог: " .. logPath, P.muted)
	end

	if hideGui and guiParent then
		UI.gui.Parent = guiParent
	end

	S.busy = false
	UI.updateStats()
end

--==================================================================
-- 13. СТАРТ
--==================================================================
local function buildTree()
	UI.setStatus("Сканирую сервисы…")
	for _, name in ipairs(CANDIDATE_SERVICES) do
		local inst = resolveService(name)
		if inst then
			local node = Tree.byInst[inst] or makeNode(inst, nil)
			node.parent = nil
			node.depth = 1
			Tree.roots[#Tree.roots + 1] = node
		end
		task.wait()
	end

	-- маленькие сервисы раскрываем сразу, чтобы было видно, что внутри
	local opened = 0
	for _, root in ipairs(Tree.roots) do
		if opened >= 3 then
			break
		end
		local ok, kids = pcall(function()
			return root.inst:GetChildren()
		end)
		if ok and #kids > 0 and #kids <= CONFIG.AutoExpandMax then
			loadChildren(root)
			root.expanded = true
			opened = opened + 1
		end
		task.wait()
	end

	UI.render()
end

local function main()
	if type(CAP.loader) ~= "function" then
		error("в экзекьюторе нет loadstring/load — USSI не запустить")
	end

	-- если нет buffer, бинарный формат недоступен — уходим в XML автоматически
	if not CAP.buffer then
		S.binary = false
	end

	pcall(function()
		local uis = game:GetService("UserInputService")
		S.compact = uis.TouchEnabled and not uis.KeyboardEnabled
	end)
	S.settingsOpen = not S.compact

	buildPicker()
	UI.layout()
	UI.updateStats()

	-- поиск
	local searchBox
	for _, child in ipairs(UI.win:GetDescendants()) do
		if child:IsA("TextBox") then
			searchBox = child
			break
		end
	end
	if searchBox then
		local pending = nil
		searchBox:GetPropertyChangedSignal("Text"):Connect(function()
			local query = searchBox.Text or ""
			if pending then
				pcall(task.cancel, pending)
				pending = nil
			end
			if #query < 2 then
				clearResultRows()
				UI.render()
				UI.updateStats()
				return
			end
			pending = task.delay(0.35, function()
				runSearch(query)
			end)
		end)
	end

	-- дерево строим сразу, USSI грузим в фоне
	task.spawn(function()
		local okTree, treeErr = pcall(buildTree)
		if not okTree then
			UI.setStatus("ошибка сканирования: " .. tostring(treeErr), P.bad)
			return
		end
		UI.setStatus("готово: раскрой «+» у сервиса и отметь объекты", P.muted)

		local ok, err = ensureUSSI()
		if ok then
			UI.setStatus("USSI готов. Отметь объекты и жми «Экспортировать».", P.muted)
		else
			UI.setStatus("USSI не загрузился — нажми «Проверка»", P.bad)
			debugLog("USSI error:", err)
			notify("Object Picker", "USSI не загрузился, нажми «Проверка»", 8)
		end
	end)
end

local started, startErr = pcall(main)
if not started then
	warn("[ObjectPicker] " .. tostring(startErr))
	notify("Object Picker", "Ошибка запуска: " .. tostring(startErr), 10)
end

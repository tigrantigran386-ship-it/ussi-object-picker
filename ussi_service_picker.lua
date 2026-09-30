--[[
================================================================================
  USSI SERVICE PICKER  —  "экспортируй только то, что я выбрал"   v1.0
================================================================================

  ЧТО ЭТО
  -------
  Обёртка над UniversalSynSaveInstance (USSI). Обычный сниппет
  (synsaveinstance(Options)) сохраняет ВСЮ клиентскую часть игры. Этот скрипт
  показывает окно со списком сервисов Roblox (Workspace, Lighting,
  ReplicatedStorage, Players, StarterGui, ...), даёт расставить галочки и
  сохраняет ТОЛЬКО выбранное: одним общим файлом или отдельным файлом на
  каждый сервис.

  ЧТО ПОД КАПОТОМ
  ---------------
  1) скрипт скачивает saveinstance.luau с GitHub и получает функцию USSI;
  2) на каждую задачу USSI вызывается с опциями:
        mode           = "selected"     -- любой НЕизвестный режим => USSI
                                        -- сохраняет только ExtraInstances
                                        -- (так написано в его документации)
        ExtraInstances = { сервис... }  -- ровно то, что отметил игрок
        IsModel        = false          -- .rbxl (place); true -> .rbxm (model)
        IgnoreList     = {}             -- ничего не выбрасывать молча
        Callback       = ...            -- файл пишем сами и знаем его размер
  3) файлы кладутся в папку workspace экзекьютора:  USSI_Export/

  ФОРМАТЫ ФАЙЛА (какой чем открывать)
  -----------------------------------
    .rbxl           PLACE-файл, то есть карта/мир. Выбранные сервисы
                    становятся корневыми сервисами плейса. Открытие:
                    Roblox Studio -> File -> Open from File.
                    Остальные сервисы Studio создаст пустыми.
                    ЭТО ТО, ЧТО НУЖНО ДЛЯ КАРТЫ.
    .rbxm           MODEL-файл. Вставляется в уже открытый плейс:
                    File -> Insert from File (или ПКМ в Explorer).
    .rbxlx / .rbxmx  То же самое, но в XML: читается глазами, но в разы
                    больше по размеру. USSI по умолчанию пишет бинарный
                    (меньше и быстрее грузится в Studio).

  ЧЕГО НЕ СМОЖЕТ НИ ЭТОТ СКРИПТ, НИ ЛЮБОЙ ДРУГОЙ
  ----------------------------------------------
    ServerStorage / ServerScriptService / серверные Script и ModuleScript
    клиенту не репликуются (FilteringEnabled). В дампе они будут ПУСТЫМИ.
    Серверный код достаётся только из утечки самого места.

  РИСКИ, О КОТОРЫХ НАДО ЗНАТЬ
  ---------------------------
    * Экзекьютор = нарушение ToS Roblox и ловится Hyperion. Только твинк.
    * Код грузится по HTTP из ветки main чужого репозитория, а сам USSI
      тянет ещё зависимости из репозитория SomeHub. Автор может подменить
      содержимое в любой момент — это supply chain риск.
    * Ассеты принадлежат их авторам: залить чужую карту в свой проект =
      нарушение авторских прав и DMCA-риск.

  ЗАПУСК
  ------
    Вставить целиком в экзекьютор и выполнить. Окно откроется сразу.
================================================================================
]]

--==================================================================
-- 1. НАСТРОЙКИ
--==================================================================
local CONFIG = {
	RepoURL = "https://raw.githubusercontent.com/luau/UniversalSynSaveInstance/main/",
	RepoURLFallback = "https://raw.githubusercontent.com/luau/SynSaveInstance/main/", -- старый путь (редирект)
	ScriptFile = "saveinstance.luau",

	OutFolder = "USSI_Export", -- папка в workspace экзекьютора
	DefaultFormat = "rbxl",    -- "rbxl" (place) | "rbxm" (model)
	DefaultLayout = "split",   -- "split" (файл на каждый сервис) | "single" (один общий)
	CountBudget = 20000,       -- глубже не считаем, показываем "20000+"
	Debug = false,             -- true -> отладочные принты в консоль (F9)
	SafeFont = false,          -- true, если вместо букв квадратики (шрифт без кириллицы)
}

-- Что показывать в списке
local CANDIDATE_SERVICES = {
	"Workspace", "Lighting", "ReplicatedFirst", "ReplicatedStorage", "StarterGui",
	"StarterPack", "StarterPlayer", "Players", "Teams", "SoundService",
	"TextChatService", "Chat", "LocalizationService", "MaterialService",
	"ServerScriptService", "ServerStorage", "JointsService", "TestService",
	"InsertService", "PhysicsService", "ProximityPromptService", "VoiceChatService",
	"CoreGui", "CorePackages",
}

-- Сервисы, которые на клиенте пустые (для предупреждения)
local SERVER_ONLY = {
	ServerStorage = true,
	ServerScriptService = true,
}

-- Предвыбранные галочки
local DEFAULT_PICKS = {
	Workspace = true,
	Lighting = true,
	ReplicatedStorage = true,
}

-- Пресеты кнопок
local PRESET_MAP = {
	map = { "Workspace", "Lighting", "MaterialService", "SoundService", "Teams" },
	scripts = {
		"ReplicatedStorage", "ReplicatedFirst", "StarterPlayer", "StarterPack",
		"StarterGui", "TextChatService", "Chat", "ServerScriptService", "ServerStorage",
	},
}

--==================================================================
-- 2. БАЗА: http, файлы, утилиты
--==================================================================
local CAP = {
	writefile = type(writefile) == "function",
	isfile = type(isfile) == "function",
	makefolder = type(makefolder) == "function",
	loader = type(loadstring) == "function" and loadstring or load,
}

local function debugLog(...)
	if CONFIG.Debug then
		print("[ServicePicker]", ...)
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

local function sanitizeName(str)
	str = string.gsub(str, "[^%w _%-%+]", "")
	str = string.gsub(str, "%s+", "_")
	str = string.sub(str, 1, 80)
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
	error("HTTP GET не удался: " .. url .. " (" .. tostring(res) .. ")")
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
		for _ = 1, 10 do
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

-- USSI при явном FilePath перезаписывает файлы, поэтому имя делаем уникальным
local function uniquePath(folder, base, ext)
	local first = folder .. "/" .. base .. ext
	if not CAP.isfile then
		return first
	end
	local ok, exists = pcall(isfile, first)
	if not ok or not exists then
		return first
	end
	local i = 1
	while i < 500 do
		local candidate = folder .. "/" .. base .. "(" .. i .. ")" .. ext
		local ok2, exists2 = pcall(isfile, candidate)
		if not ok2 or not exists2 then
			return candidate
		end
		i = i + 1
	end
	return first
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

-- обход дерева без GetDescendants() (не создаём гигантскую таблицу)
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

--==================================================================
-- 3. UI-ТУЛКИТ
--==================================================================
local P = {
	bg = Color3.fromRGB(13, 14, 18),
	panel = Color3.fromRGB(23, 25, 32),
	panel2 = Color3.fromRGB(32, 35, 44),
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
		TextSize = 13,
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

-- кнопка: возвращает таблицу { frame, label, hit }
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
		TextSize = props.textSize or 13,
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
	}, frame)

	hit.MouseEnter:Connect(function()
		frame.BackgroundColor3 = props.hover or P.accentSoft
	end)
	hit.MouseLeave:Connect(function()
		frame.BackgroundColor3 = props.bg or P.panel2
	end)
	if props.onClick then
		hit.MouseButton1Click:Connect(props.onClick)
	end

	return { frame = frame, label = text, hit = hit }
end

-- галочка; возвращает функцию чтения состояния
local function toggle(parent, text, default, position, width)
	local holder = new("Frame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(0, width or 250, 0, 24),
		Position = position or UDim2.new(0, 0, 0, 0),
	}, parent)

	local box = new("Frame", {
		BackgroundColor3 = P.panel2,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 16, 0, 16),
		Position = UDim2.new(0, 0, 0.5, -8),
	}, holder)
	corner(box, 4)
	stroke(box, P.line, 1, 0.3)

	local mark = new("Frame", {
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		Size = UDim2.new(0, 8, 0, 8),
		Position = UDim2.new(0.5, -4, 0.5, -4),
	}, box)
	corner(mark, 2)

	label(holder, {
		Text = text,
		TextSize = 12,
		TextColor3 = P.muted,
		Size = UDim2.new(1, -26, 1, 0),
		Position = UDim2.new(0, 26, 0, 0),
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
	}, holder)
	hit.MouseButton1Click:Connect(function()
		state = not state
		render()
	end)

	return function()
		return state
	end
end

-- выбор из вариантов; возвращает функцию принудительного выбора
local function segmented(parent, items, defaultIndex, position, buttonWidth, onSelect)
	local height = 30
	local holder = new("Frame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(0, (#items * buttonWidth) + (4 * (#items - 1)), 0, height),
		Position = position or UDim2.new(0, 0, 0, 0),
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
		local btn = button(holder, {
			text = items[i],
			size = UDim2.new(0, buttonWidth, 0, height),
			position = UDim2.new(0, (i - 1) * (buttonWidth + 4), 0, 0),
			textSize = 12,
			bg = P.panel2,
			onClick = function()
				select(i)
			end,
		})
		buttons[i] = btn
	end

	select(defaultIndex or 1, true)
	return select
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

--==================================================================
-- 4. ЗАГРУЗКА USSI
--==================================================================
local USSI = nil

local function loadUSSI()
	debugLog("скачиваю USSI")
	local source
	local ok = pcall(function()
		source = httpGet(CONFIG.RepoURL .. CONFIG.ScriptFile)
	end)
	if not ok then
		source = httpGet(CONFIG.RepoURLFallback .. CONFIG.ScriptFile)
	end
	if type(source) ~= "string" or #source < 1000 then
		error("USSI: пустой ответ от GitHub")
	end
	if type(CAP.loader) ~= "function" then
		error("USSI: в экзекьюторе нет loadstring/load")
	end
	local chunk, loadErr = CAP.loader(source, "USSI_saveinstance")
	if not chunk then
		error("USSI: не скомпилировался — " .. tostring(loadErr))
	end
	local fn = chunk()
	if type(fn) ~= "function" then
		error("USSI: модуль вернул не функцию, а " .. typeof(fn))
	end
	debugLog("USSI загружен, размер исходника:", #source)
	return fn
end

--==================================================================
-- 5. СОСТОЯНИЕ + СБОРКА ОКНА
--==================================================================
local S = {
	format = CONFIG.DefaultFormat,
	layout = CONFIG.DefaultLayout,
	filter = "",
	rows = {},
	busy = false,
	cancelled = false,
	scanning = true,
}

local UI = {
	rows = {},
	picked = 0,
}

local ROW_H = 32
local ROW_GAP = 6

local function buildPicker()
	local parent = getGuiParent()
	if not parent then
		error("не нашёл, куда положить интерфейс (CoreGui / PlayerGui)")
	end

	-- если скрипт запускают повторно — убираем прошлое окно
	for _, child in ipairs(parent:GetChildren()) do
		if child.Name == "USSI_ServicePicker" then
			pcall(function()
				child:Destroy()
			end)
		end
	end

	local gui = new("ScreenGui", {
		Name = "USSI_ServicePicker",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		DisplayOrder = 9999,
		IgnoreGuiInset = true,
	}, parent)
	UI.gui = gui

	local viewport = Vector2.new(1280, 720)
	local cam = workspace.CurrentCamera
	if cam then
		viewport = cam.ViewportSize
	end

	local W = math.clamp(viewport.X - 60, 400, 640)
	local H = math.clamp(viewport.Y - 60, 520, 760)
	local PAD = 14
	local HEAD_H = 46
	local TOOL_H = 32
	local PRESET_H = 26
	local PANEL_H = 172
	local BTN_H = 44

	local win = new("Frame", {
		BackgroundColor3 = P.bg,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, W, 0, H),
	}, gui)
	corner(win, 12)
	stroke(win, P.line, 1, 0.25)
	UI.win = win

	-- ---------- шапка ----------
	label(win, {
		Text = "USSI Service Picker",
		Font = FONT_BOLD,
		TextSize = 17,
		Position = UDim2.new(0, PAD, 0, PAD),
		Size = UDim2.new(1, -(PAD * 2) - 40, 0, 20),
	})
	label(win, {
		Text = "Экспорт только выбранных сервисов Roblox в .rbxl / .rbxm",
		TextSize = 12,
		TextColor3 = P.muted,
		Position = UDim2.new(0, PAD, 0, PAD + 22),
		Size = UDim2.new(1, -(PAD * 2) - 40, 0, 16),
	})

	local closeBtn = button(win, {
		text = "X",
		size = UDim2.new(0, 28, 0, 28),
		position = UDim2.new(1, -PAD - 28, 0, PAD + 2),
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

	-- ---------- поиск + кнопки отметки ----------
	local toolY = PAD + HEAD_H + 4

	local search = new("TextBox", {
		BackgroundColor3 = P.panel2,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = FONT,
		PlaceholderText = "поиск сервиса...",
		PlaceholderColor3 = P.muted,
		Text = "",
		TextColor3 = P.text,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(0, 180, 0, TOOL_H),
		Position = UDim2.new(0, PAD, 0, toolY),
	}, win)
	corner(search, 6)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8) }, search)
	search:GetPropertyChangedSignal("Text"):Connect(function()
		S.filter = string.lower(search.Text or "")
		UI.relayout()
	end)

	UI.selLabel = label(win, {
		Text = "выбрано: 0",
		TextSize = 12,
		TextColor3 = P.muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		Size = UDim2.new(0, 120, 0, TOOL_H),
		Position = UDim2.new(1, -PAD - 120, 0, toolY),
	})

	local function markAll(mode)
		for _, entry in ipairs(S.rows) do
			if entry.instance then
				if mode == "all" then
					entry.checked = true
				elseif mode == "none" then
					entry.checked = false
				else
					entry.checked = not entry.checked
				end
				UI.updateRow(entry)
			end
		end
		UI.updateSelection()
	end

	button(win, {
		text = "Все",
		size = UDim2.new(0, 74, 0, TOOL_H),
		position = UDim2.new(1, -(PAD + 120 + 78 + 6 + 74 + 6 + 74), 0, toolY),
		textSize = 12,
		onClick = function()
			markAll("all")
		end,
	})
	button(win, {
		text = "Ничего",
		size = UDim2.new(0, 74, 0, TOOL_H),
		position = UDim2.new(1, -(PAD + 120 + 78 + 6 + 74), 0, toolY),
		textSize = 12,
		onClick = function()
			markAll("none")
		end,
	})
	button(win, {
		text = "Инверсия",
		size = UDim2.new(0, 74, 0, TOOL_H),
		position = UDim2.new(1, -(PAD + 120 + 78), 0, toolY),
		textSize = 12,
		onClick = function()
			markAll("invert")
		end,
	})

	-- ---------- пресеты + добавление сервиса ----------
	local presetY = toolY + TOOL_H + 6
	local presetX = PAD

	local function presetButton(text, width, names, onlyNonEmpty)
		button(win, {
			text = text,
			size = UDim2.new(0, width, 0, PRESET_H),
			position = UDim2.new(0, presetX, 0, presetY),
			textSize = 11,
			onClick = function()
				local wanted = {}
				if names then
					for _, n in ipairs(names) do
						wanted[n] = true
					end
				end
				for _, entry in ipairs(S.rows) do
					if not entry.instance then
						entry.checked = false
					elseif onlyNonEmpty then
						entry.checked = (entry.count or 0) > 0
					elseif wanted[entry.name] then
						entry.checked = true
					end
					UI.updateRow(entry)
				end
				UI.updateSelection()
			end,
		})
		presetX = presetX + width + 6
	end

	presetButton("Карта", 74, PRESET_MAP.map, false)
	presetButton("Скрипты", 82, PRESET_MAP.scripts, false)
	presetButton("Всё, что не пустое", 140, nil, true)

	local addBox = nil
	button(win, {
		text = "+ сервис",
		size = UDim2.new(0, 84, 0, PRESET_H),
		position = UDim2.new(1, -PAD - 84, 0, presetY),
		textSize = 11,
		onClick = function()
			if addBox then
				return
			end
			addBox = new("TextBox", {
				BackgroundColor3 = P.panel2,
				BorderSizePixel = 0,
				ClearTextOnFocus = false,
				Font = FONT,
				PlaceholderText = "имя сервиса, потом Enter",
				PlaceholderColor3 = P.muted,
				Text = "",
				TextColor3 = P.text,
				TextSize = 12,
				Size = UDim2.new(0, 210, 0, PRESET_H),
				Position = UDim2.new(1, -PAD - 84 - 6 - 210, 0, presetY),
			}, win)
			corner(addBox, 6)
			new("UIPadding", { PaddingLeft = UDim.new(0, 8) }, addBox)
			addBox:CaptureFocus()
			addBox.FocusLost:Connect(function(enterPressed)
				local value = addBox.Text or ""
				addBox:Destroy()
				addBox = nil
				if enterPressed and value ~= "" then
					UI.addCustom(value)
				end
			end)
		end,
	})

	-- ---------- список сервисов ----------
	local listY = presetY + PRESET_H + 8
	local STATUS_H = 16
	local panelY = H - PAD - STATUS_H - 4 - BTN_H - 6 - PANEL_H
	local listH = math.max(120, panelY - 10 - listY)

	UI.list = new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.new(0, PAD, 0, listY),
		Size = UDim2.new(1, -PAD * 2, 0, listH),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = P.accent,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, win)
	new("UIListLayout", {
		Padding = UDim.new(0, ROW_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, UI.list)

	-- ---------- нижняя панель настроек ----------
	local panel = new("Frame", {
		BackgroundColor3 = P.panel,
		BorderSizePixel = 0,
		Position = UDim2.new(0, PAD, 0, panelY),
		Size = UDim2.new(1, -PAD * 2, 0, PANEL_H),
	}, win)
	corner(panel, 10)

	label(panel, {
		Text = "Формат:",
		TextSize = 12,
		TextColor3 = P.muted,
		Position = UDim2.new(0, 14, 0, 14),
		Size = UDim2.new(0, 80, 0, 30),
	})
	segmented(panel, { ".rbxl плейс", ".rbxm модель" }, S.format == "rbxl" and 1 or 2, UDim2.new(0, 92, 0, 14), 96, function(_, value)
		S.format = (value == ".rbxl плейс") and "rbxl" or "rbxm"
	end)

	label(panel, {
		Text = "Файлы:",
		TextSize = 12,
		TextColor3 = P.muted,
		Position = UDim2.new(0, 14, 0, 52),
		Size = UDim2.new(0, 80, 0, 30),
	})
	segmented(panel, { "на каждый", "один общий" }, S.layout == "split" and 1 or 2, UDim2.new(0, 92, 0, 52), 96, function(_, value)
		S.layout = (value == "на каждый") and "split" or "single"
	end)

	local panelW = W - PAD * 2
	local toggleX = math.clamp(panelW - 274, 230, 320)
	local toggleW = math.max(150, panelW - toggleX - 14)

	label(panel, {
		Text = ".rbxl — плейс (карта): File → Open from File.\n"
			.. ".rbxm — модель: File → Insert from File.\n"
			.. "ServerStorage / ServerScriptService придут пустыми:\nклиенту они не репликуются.",
		TextSize = 11,
		TextColor3 = P.muted,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.new(0, 14, 0, 92),
		Size = UDim2.new(0, math.max(150, toggleX - 26), 0, 76),
	})

	UI.getDecompile = toggle(panel, "Декомпилировать скрипты (Decompile)", true, UDim2.new(0, toggleX, 0, 14), toggleW)
	UI.getBytecode = toggle(panel, "Сохранять байткод (SaveBytecode)", false, UDim2.new(0, toggleX, 0, 40), toggleW)
	UI.getReadme = toggle(panel, "ReadMe-скрипт с заметками", true, UDim2.new(0, toggleX, 0, 66), toggleW)
	UI.getNil = toggle(panel, "NilInstances (объекты без родителя)", false, UDim2.new(0, toggleX, 0, 92), toggleW)
	UI.getSafe = toggle(panel, "SafeMode (кикнет перед сохранением)", false, UDim2.new(0, toggleX, 0, 118), toggleW)

	-- ---------- статус + кнопка экспорта ----------
	UI.status = label(win, {
		Text = "Запускаюсь…",
		TextSize = 11,
		TextColor3 = P.muted,
		Position = UDim2.new(0, PAD, 1, -PAD - STATUS_H),
		Size = UDim2.new(1, -PAD * 2, 0, 14),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	local exportBtn = button(win, {
		text = "ЭКСПОРТИРОВАТЬ",
		size = UDim2.new(1, -PAD * 2, 0, BTN_H),
		position = UDim2.new(0, PAD, 1, -(PAD + STATUS_H + 4 + BTN_H)),
		bg = P.accent,
		hover = P.accentHover,
		bold = true,
		textSize = 15,
		onClick = function()
			UI.requestExport()
		end,
	})
	UI.exportBtn = exportBtn

	UI.setStatus = function(text, color)
		UI.status.Text = text or ""
		UI.status.TextColor3 = color or P.muted
	end

	-- ---------- окно подтверждения ----------
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
		Size = UDim2.new(0, math.min(440, W - 40), 0, 260),
		ZIndex = 21,
	}, modalHolder)
	corner(modalPanel, 10)
	stroke(modalPanel, P.line, 1, 0.2)

	local modalTitle = label(modalPanel, {
		Text = "Подтверждение",
		Font = FONT_BOLD,
		TextSize = 15,
		Position = UDim2.new(0, 16, 0, 14),
		Size = UDim2.new(1, -32, 0, 18),
		ZIndex = 21,
	})
	local modalText = label(modalPanel, {
		Text = "",
		TextSize = 12,
		TextColor3 = P.muted,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.new(0, 16, 0, 40),
		Size = UDim2.new(1, -32, 1, -108),
		ZIndex = 21,
	})

	local okBtn = button(modalPanel, {
		text = "Экспортировать",
		size = UDim2.new(0, 160, 0, 36),
		position = UDim2.new(1, -176, 1, -50),
		bg = P.accent,
		hover = P.accentHover,
		bold = true,
		onClick = function()
			modalHolder.Visible = false
			if UI.onConfirm then
				local fn = UI.onConfirm
				UI.onConfirm = nil
				fn()
			end
		end,
	})
	local cancelBtn = button(modalPanel, {
		text = "Отмена",
		size = UDim2.new(0, 110, 0, 36),
		position = UDim2.new(1, -294, 1, -50),
		onClick = function()
			modalHolder.Visible = false
		end,
	})
	for _, item in ipairs({ { okBtn, 22 }, { cancelBtn, 22 } }) do
		item[1].frame.ZIndex = 21
		item[1].label.ZIndex = 21
		item[1].hit.ZIndex = item[2]
	end

	UI.confirm = function(title, text, onConfirm)
		modalTitle.Text = title or "Подтверждение"
		modalText.Text = text or ""
		UI.onConfirm = onConfirm
		modalHolder.Visible = true
	end

	return gui
end

--==================================================================
-- 6. СТРОКИ СПИСКА, ФИЛЬТР, ГАЛОЧКИ, СКАНИРОВАНИЕ
--==================================================================
local function makeRow(entry)
	local row = new("Frame", {
		Name = entry.name,
		BackgroundColor3 = P.panel,
		BorderSizePixel = 0,
		Size = UDim2.new(1, -8, 0, ROW_H),
		LayoutOrder = entry.order,
	}, UI.list)
	corner(row, 6)

	local box = new("Frame", {
		BackgroundColor3 = P.panel2,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 16, 0, 16),
		Position = UDim2.new(0, 10, 0.5, -8),
	}, row)
	corner(box, 4)

	local mark = new("Frame", {
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		Size = UDim2.new(0, 8, 0, 8),
		Position = UDim2.new(0.5, -4, 0.5, -4),
	}, box)
	corner(mark, 2)

	local nameLbl = label(row, {
		Text = entry.name,
		Font = FONT_BOLD,
		TextSize = 13,
		Position = UDim2.new(0, 36, 0, 0),
		Size = UDim2.new(0, 200, 1, 0),
	})

	local badge = label(row, {
		Text = "",
		TextSize = 10,
		TextColor3 = P.warn,
		Position = UDim2.new(0, 240, 0, 0),
		Size = UDim2.new(0, 150, 1, 0),
	})

	local countLbl = label(row, {
		Text = "…",
		TextSize = 12,
		TextColor3 = P.muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(1, -150, 0, 0),
		Size = UDim2.new(0, 140, 1, 0),
	})

	local hit = new("TextButton", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		Text = "",
		AutoButtonColor = false,
	}, row)
	hit.MouseEnter:Connect(function()
		row.BackgroundColor3 = P.panel2
	end)
	hit.MouseLeave:Connect(function()
		row.BackgroundColor3 = P.panel
	end)
	hit.MouseButton1Click:Connect(function()
		if entry.instance == nil or S.busy then
			return
		end
		entry.checked = not entry.checked
		UI.updateRow(entry)
		UI.updateSelection()
	end)

	entry.row = row
	entry.mark = mark
	entry.box = box
	entry.countLbl = countLbl
	entry.badge = badge
	entry.nameLbl = nameLbl
end

function UI.updateRow(entry)
	local usable = entry.instance ~= nil
	entry.mark.Visible = entry.checked and usable
	entry.box.BackgroundColor3 = (entry.checked and usable) and P.accent or P.panel2
	if not usable then
		entry.nameLbl.TextColor3 = Color3.fromRGB(110, 114, 126)
		entry.countLbl.Text = "—"
		entry.badge.Text = "нет на клиенте"
		entry.badge.TextColor3 = P.muted
	elseif SERVER_ONLY[entry.name] then
		entry.nameLbl.TextColor3 = P.text
		entry.badge.Text = "только сервер → пусто"
		entry.badge.TextColor3 = P.warn
	else
		entry.nameLbl.TextColor3 = P.text
	end
end

function UI.updateSelection()
	local total = 0
	for _, entry in ipairs(S.rows) do
		if entry.checked and entry.instance then
			total = total + 1
		end
	end
	UI.picked = total
	UI.selLabel.Text = "выбрано: " .. total
	UI.exportBtn.label.Text = total > 0 and ("ЭКСПОРТИРОВАТЬ (" .. total .. ")") or "ЭКСПОРТИРОВАТЬ"
end

function UI.relayout()
	local visible = 0
	local filter = S.filter
	for _, entry in ipairs(S.rows) do
		local show = true
		if filter ~= "" then
			show = string.find(string.lower(entry.name), filter, 1, true) ~= nil
		end
		entry.row.Visible = show
		if show then
			visible = visible + 1
		end
	end
	UI.list.CanvasSize = UDim2.new(0, 0, 0, visible * (ROW_H + ROW_GAP))
end

function UI.reorder()
	local sorted = {}
	for _, entry in ipairs(S.rows) do
		sorted[#sorted + 1] = entry
	end
	table.sort(sorted, function(a, b)
		local ac = a.count
		local bc = b.count
		if ac == nil then
			ac = a.instance and 0 or -1
		end
		if bc == nil then
			bc = b.instance and 0 or -1
		end
		if ac == bc then
			return a.name < b.name
		end
		return ac > bc
	end)
	for index, entry in ipairs(sorted) do
		entry.row.LayoutOrder = index
	end
	UI.relayout()
end

local function addEntry(name, instance, preselected)
	local entry = {
		name = name,
		instance = instance,
		checked = (preselected == true) and instance ~= nil,
		count = nil,
		truncated = false,
		order = #S.rows + 1,
	}
	S.rows[#S.rows + 1] = entry
	makeRow(entry)
	UI.updateRow(entry)
	return entry
end

UI.addCustom = function(rawName)
	local name = string.gsub(rawName or "", "%s", "")
	if name == "" then
		return
	end
	for _, entry in ipairs(S.rows) do
		if string.lower(entry.name) == string.lower(name) then
			UI.setStatus("«" .. entry.name .. "» уже есть в списке", P.warn)
			return
		end
	end
	local inst = resolveService(name)
	if not inst then
		UI.setStatus("«" .. name .. "» недоступен на клиенте", P.bad)
		return
	end
	local entry = addEntry(inst.Name or name, inst, true)
	UI.updateSelection()
	UI.setStatus("Добавлен сервис: " .. entry.name, P.ok)
	task.spawn(function()
		local total, truncated = countInstances(inst, CONFIG.CountBudget)
		entry.count, entry.truncated = total, truncated
		entry.countLbl.Text = total .. (truncated and "+" or "") .. " объектов"
		UI.reorder()
	end)
end

local function scanAll()
	UI.setStatus("Сканирую сервисы игры…")
	for _, name in ipairs(CANDIDATE_SERVICES) do
		local inst = resolveService(name)
		local entry = addEntry(name, inst, DEFAULT_PICKS[name] == true)
		entry.countLbl.Text = inst and "…" or "—"
		task.wait()
	end
	UI.updateSelection()
	UI.relayout()

	local done = 0
	for _, entry in ipairs(S.rows) do
		if entry.instance then
			local total, truncated = countInstances(entry.instance, CONFIG.CountBudget)
			entry.count, entry.truncated = total, truncated
			entry.countLbl.Text = total .. (truncated and "+" or "") .. " объектов"
			if total == 0 then
				entry.countLbl.TextColor3 = Color3.fromRGB(100, 104, 116)
			end
		end
		done = done + 1
		UI.setStatus(string.format("Считаю объекты… %d/%d", done, #S.rows))
		task.wait()
	end

	S.scanning = false
	UI.reorder()
	UI.setStatus(string.format("Сервисов: %d. Отметь нужные и жми «Экспортировать».", #S.rows))
	debugLog("scan done")
end

--==================================================================
-- 7. ОВЕРЛЕЙ ПРОГРЕССА
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

	local dim = new("Frame", {
		BackgroundColor3 = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
	}, gui)

	local panel = new("Frame", {
		BackgroundColor3 = P.bg,
		BorderSizePixel = 0,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.5, 0),
		Size = UDim2.new(0, 480, 0, 330),
	}, dim)
	corner(panel, 12)
	stroke(panel, P.line, 1, 0.25)

	local title = label(panel, {
		Text = "Экспорт…",
		Font = FONT_BOLD,
		TextSize = 16,
		Position = UDim2.new(0, 16, 0, 14),
		Size = UDim2.new(1, -32, 0, 20),
	})

	local jobLbl = label(panel, {
		Text = "подготовка",
		TextSize = 12,
		TextColor3 = P.muted,
		Position = UDim2.new(0, 16, 0, 36),
		Size = UDim2.new(1, -32, 0, 16),
	})

	local barBg = new("Frame", {
		BackgroundColor3 = P.panel2,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 16, 0, 58),
		Size = UDim2.new(1, -32, 0, 8),
	}, panel)
	corner(barBg, 4)
	local barFill = new("Frame", {
		BackgroundColor3 = P.accent,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 0, 1, 0),
	}, barBg)
	corner(barFill, 4)

	local logBox = new("ScrollingFrame", {
		BackgroundColor3 = P.panel,
		BorderSizePixel = 0,
		Position = UDim2.new(0, 16, 0, 78),
		Size = UDim2.new(1, -32, 1, -78 - 62),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ScrollBarThickness = 4,
		ScrollBarImageColor3 = P.accent,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, panel)
	corner(logBox, 8)
	new("UIPadding", {
		PaddingTop = UDim.new(0, 8),
		PaddingBottom = UDim.new(0, 8),
		PaddingLeft = UDim.new(0, 8),
		PaddingRight = UDim.new(0, 8),
	}, logBox)
	local logLayout = new("UIListLayout", {
		Padding = UDim.new(0, 4),
		SortOrder = Enum.SortOrder.LayoutOrder,
	}, logBox)

	local lineCount = 0

	local function refreshLog()
		logBox.CanvasSize = UDim2.new(0, 0, 0, logLayout.AbsoluteContentSize.Y + 16)
		local canvas = logBox.AbsoluteCanvasSize.Y
		local view = logBox.AbsoluteSize.Y
		if canvas > view then
			logBox.CanvasPosition = Vector2.new(0, canvas - view)
		end
	end

	local function addLog(text, color)
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

	local ov = {
		gui = gui,
		panel = panel,
		addLog = addLog,
	}

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

	local actionBtn = button(panel, {
		text = "Отмена",
		size = UDim2.new(0, 130, 0, 36),
		position = UDim2.new(1, -146, 1, -52),
		onClick = function()
			if S.busy then
				S.cancelled = true
				ov.setTitle("Останавливаюсь…", P.warn)
				actionBtn.label.Text = "Ждите…"
			else
				ov.destroy()
			end
		end,
	})
	ov.actionBtn = actionBtn

	ov.finish = function(titleText, color, buttonText)
		ov.setTitle(titleText, color)
		ov.setJob("")
		ov.setProgress(1)
		actionBtn.label.Text = buttonText or "Готово"
	end

	ov.destroy = function()
		pcall(function()
			gui:Destroy()
		end)
	end

	return ov
end

--==================================================================
-- 8. ЭКСПОРТ
--==================================================================
local function buildJobs(picked)
	local jobs = {}
	if S.layout == "single" then
		local instances, names = {}, {}
		for _, entry in ipairs(picked) do
			instances[#instances + 1] = entry.instance
			names[#names + 1] = entry.name
		end
		local joined = table.concat(names, "+")
		jobs[1] = {
			title = table.concat(names, ", "),
			fileBase = sanitizeName("Selected_" .. os.date("%Y%m%d_%H%M%S")),
			instances = instances,
		}
		debugLog("single job:", joined)
	else
		for _, entry in ipairs(picked) do
			jobs[#jobs + 1] = {
				title = entry.name,
				fileBase = sanitizeName(entry.name),
				instances = { entry.instance },
			}
		end
	end
	return jobs
end

local function runOne(job, path)
	local genv = getGenv()
	-- USSI держит глобальную защиту от повторного сохранения того же пути
	genv[path] = nil

	local result = { ok = false, size = nil, err = nil }

	local options = {
		-- любой неизвестный режим => USSI сохраняет ТОЛЬКО ExtraInstances
		mode = "selected",

		ExtraInstances = job.instances,
		IsModel = (S.format == "rbxm"),

		-- ничего не выбрасывать: игрок сам решил, что ему нужно
		IgnoreList = {},
		DecompileIgnore = {},

		Binary = true,        -- .rbxl/.rbxm вместо .rbxlx/.rbxmx
		CompressionMode = "zstd",
		CompressionLevel = 9,

		Decompile = UI.getDecompile(),
		scriptcache = true,
		SaveBytecode = UI.getBytecode(),
		DecompileTimeout = 20,

		ReadMe = UI.getReadme(),
		NilInstances = UI.getNil(),

		IgnoreDefaultProperties = true,
		IgnoreNotArchivable = true,
		SaveNotCreatable = false,

		SafeMode = UI.getSafe(),
		KillAllScripts = UI.getSafe(),
		ShutdownWhenDone = false,
		BoostFPS = false,
		AntiIdle = true,
		ShowStatus = false,   -- свой прогресс, не нужен второй оверлей
		__DEBUG_MODE = CONFIG.Debug,

		FilePath = path,
		AvoidFileOverwrite = false,

		-- файл пишем сами: так мы точно знаем, что сохранение получилось
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
			if type(writefile) ~= "function" then
				result.err = "в экзекьюторе нет writefile"
				return
			end
			local written, writeErr = pcall(writefile, path, payload)
			if written then
				result.ok = true
				result.size = #payload
			else
				result.err = tostring(writeErr)
			end
		end,
	}

	local called, callErr = pcall(USSI, options)
	if not called then
		result.ok = false
		result.err = tostring(callErr)
	end
	if not result.ok and not result.err then
		result.err = "USSI не отдал данные (смотри консоль F9)"
	end
	return result
end

-- эти сервисы содержат наш собственный интерфейс, поэтому окно прячем
local function hasPlayersOrGui(picked)
	for _, entry in ipairs(picked) do
		if entry.name == "Players" or entry.name == "CoreGui" or entry.name == "PlayerGui" then
			return true
		end
	end
	return false
end

function UI.runExport(picked)
	S.busy = true
	S.cancelled = false

	local hasPlayers = hasPlayersOrGui(picked)

	-- чтобы наше окно не попало в дамп вместе с Players/PlayerGui
	local guiParent = UI.gui.Parent
	if hasPlayers then
		UI.gui.Parent = nil
	end

	local ov = createOverlay()
	ov.addLog("Папка: " .. CONFIG.OutFolder .. "/", P.text)
	if hasPlayers then
		ov.addLog("Окно выбора скрыто на время дампа (выбраны Players/CoreGui).", P.warn)
	end

	if CAP.makefolder then
		pcall(makefolder, CONFIG.OutFolder)
	end

	local jobs = buildJobs(picked)
	local totalBytes = 0
	local okCount = 0

	for index, job in ipairs(jobs) do
		if S.cancelled then
			ov.addLog("Остановлено пользователем.", P.warn)
			break
		end

		ov.setProgress((index - 1) / #jobs)
		ov.setJob(string.format("(%d/%d) %s — сохраняю…", index, #jobs, job.title))
		ov.addLog(string.format("▶ %s", job.title), P.text)

		local ext = (S.format == "rbxm") and ".rbxm" or ".rbxl"
		local path = uniquePath(CONFIG.OutFolder, job.fileBase, ext)
		local result = runOne(job, path)

		if result.ok then
			okCount = okCount + 1
			totalBytes = totalBytes + (result.size or 0)
			ov.addLog(string.format("  ✓ готово — %s (%s)", path, fmtSize(result.size)), P.ok)
		else
			ov.addLog(string.format("  ✗ ошибка — %s", tostring(result.err)), P.bad)
		end
		ov.setProgress(index / #jobs)

		local okRefresh, errRefresh = pcall(function()
			-- страховка: файл мог не появиться, если экзекьютор не поддержал writefile
			if result.ok and CAP.isfile and not isfile(path) then
				ov.addLog("  ! файл не найден на диске после записи", P.warn)
			end
		end)
		if not okRefresh and CONFIG.Debug then
			debugLog("refresh fail", errRefresh)
		end

		task.wait(0.25) -- дать движку подышать между дампами
	end

	if S.cancelled then
		ov.finish("Остановлено", P.warn)
	elseif okCount == 0 then
		ov.finish("Ничего не сохранилось", P.bad)
	elseif okCount < #jobs then
		ov.finish(string.format("Готово частично: %d из %d, %s", okCount, #jobs, fmtSize(totalBytes)), P.warn)
	else
		ov.finish(string.format("Готово: %d файл(ов), %s", okCount, fmtSize(totalBytes)), P.ok)
	end

	ov.addLog("Файлы лежат в workspace/" .. CONFIG.OutFolder .. "/ (у экзекьютора).", P.muted)

	if hasPlayers and guiParent then
		UI.gui.Parent = guiParent
	end

	S.busy = false
	S.cancelled = false

	-- вернуть пикеру возможность экспортировать снова
	if UI.status then
		UI.setStatus("Экспорт завершён. Можно выбрать другое и повторить.", P.muted)
	end
end

function UI.requestExport()
	if S.busy then
		return
	end
	if not USSI then
		UI.setStatus("USSI ещё не загружен — подожди пару секунд", P.warn)
		return
	end
	if not CAP.writefile then
		UI.setStatus("Экзекьютор без writefile — файлы сохранить некуда", P.bad)
		notify("Service Picker", "Нужен экзекьютор с writefile", 8)
		return
	end

	local picked = {}
	for _, entry in ipairs(S.rows) do
		if entry.checked and entry.instance then
			picked[#picked + 1] = entry
		end
	end
	if #picked == 0 then
		UI.setStatus("Ничего не отмечено", P.warn)
		return
	end

	local names, serverOnly = {}, {}
	for _, entry in ipairs(picked) do
		names[#names + 1] = entry.name
		if SERVER_ONLY[entry.name] then
			serverOnly[#serverOnly + 1] = entry.name
		end
	end

	local text = string.format(
		"Будет сохранено %d сервис(ов), режим: %s, формат: .%s.\n\n%s",
		#picked,
		(S.layout == "single") and "один общий файл" or "отдельный файл на сервис",
		S.format,
		table.concat(names, ", ")
	)
	if #serverOnly > 0 then
		text = text
			.. "\n\nВнимание: "
			.. table.concat(serverOnly, ", ")
			.. " клиенту не репликуются — в файле они будут пустыми."
	end
	if hasPlayersOrGui(picked) then
		text = text .. "\n\nОкно скрипта на время экспорта будет скрыто, чтобы не попасть в дамп."
	end

	UI.confirm("Экспорт " .. #picked .. " сервис(ов)", text, function()
		UI.runExport(picked)
	end)
end

--==================================================================
-- 9. СТАРТ
--==================================================================
local function main()
	if type(CAP.loader) ~= "function" then
		error("экзекьютор без loadstring/load — USSI не запустить")
	end
	buildPicker()
	UI.updateSelection()
	UI.setStatus("Загружаю USSI с GitHub…")

	task.spawn(function()
		local okLoad, loadErr = pcall(function()
			USSI = loadUSSI()
		end)
		if not okLoad then
			UI.setStatus("Ошибка загрузки USSI: " .. tostring(loadErr), P.bad)
			notify("Service Picker", "Не смог загрузить USSI. Детали — в консоли (F9).", 10)
			return
		end
		UI.setStatus("USSI загружен. Сканирую сервисы…", P.ok)

		local okScan, scanErr = pcall(scanAll)
		if not okScan then
			UI.setStatus("Ошибка сканирования: " .. tostring(scanErr), P.bad)
			if CONFIG.Debug then
				warn(scanErr)
			end
		end
	end)
end

local started, startErr = pcall(main)
if not started then
	warn("[ServicePicker] " .. tostring(startErr))
	notify("Service Picker", "Ошибка запуска: " .. tostring(startErr), 10)
end

--[[
================================================================================
  USSI OBJECT PICKER  —  "выбери конкретные объекты и сохрани ТОЛЬКО их"   v2.0
================================================================================

  ЧТО ЭТО
  -------
  Обёртка над UniversalSynSaveInstance (USSI) с деревом объектов.

  Ты раскрываешь сервис (Workspace, ReplicatedStorage, Lighting, ...), идёшь по
  дереву как в Explorer'е и отмечаешь галочками КОНКРЕТНЫЕ объекты: модели,
  парты, папки, скрипты. Можно набрать их из разных сервисов сразу.
  При экспорте сохраняется ТОЛЬКО выбранное — в один файл.

  Обычный saveinstance копирует всю карту; этот скрипт копирует только
  выбранные ветки.

  ДВА РЕЖИМА СОХРАНЕНИЯ (переключатель «Формат»)
  ----------------------------------------------
    .rbxl  «как карта, с путями»
           Итог — place-файл, в котором выбранные объекты лежат НА СВОИХ
           МЕСТАХ: Workspace → Folder → Model будет именно там же, а всё
           остальное отрезано. Открывается: Studio → File → Open from File.
           Реализовано через IgnoreList: USSI'у передаётся корнем весь
           сервис, а все ветки, которые ведут не к твоему выбору,
           помечаются как игнорируемые.

    .rbxm  «как модель»
           Итог — model-файл, где выбранные объекты лежат списком сверху.
           Вставляется в открытый проект: File → Insert from File.
           Полезно, когда нужны сами объекты, а не структура карты.

  ЧТО ПОД КАПОТОМ (для любопытных)
  --------------------------------
   * saveinstance.luau скачивается с GitHub и запускается как функция USSI;
   * каждый экспорт = один вызов USSI:
        mode = "selected"        -- неизвестный режим => только ExtraInstances
        ExtraInstances = корни   -- сервисы (.rbxl) или сами объекты (.rbxm)
        IgnoreList = { [instance] = true, ... }  -- отрезанные ветки
        Callback = ...           -- файл пишем сами, поэтому знаем размер и видим ошибки
   * файлы складываются в папку workspace экзекьютора: USSI_Export/

  ЧЕГО НЕ СМОЖЕТ НИ ЭТОТ СКРИПТ, НИ ЛЮБОЙ ДРУГОЙ
  ----------------------------------------------
    ServerStorage / ServerScriptService и серверные Script/ModuleScript
    клиенту не репликуются (FilteringEnabled): в дереве они будут пустыми.
    Серверный код достаётся только из утечки самого места.

  РИСКИ
  -----
    * Экзекьютор = нарушение ToS Roblox, ловится Hyperion. Только твинк.
    * Код грузится по HTTP из ветки main чужого репозитория (плюс сам USSI
      тянет зависимости из SomeHub) — supply chain риск.
    * Ассеты принадлежат авторам: использовать чужое в своём проекте —
      нарушение авторских прав и DMCA-риск.

  УПРАВЛЕНИЕ
  ----------
    "+" / "−"  — раскрыть / свернуть ветку
    клик по строке — отметить или снять объект (галочка)
    клик по галочке у родителя, где есть отметки внутри — исключить ветку
    поиск сверху ищет по всем сервисам и показывает путь к объекту
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
	DefaultFormat = "rbxl",    -- "rbxl" (как карта, с путями) | "rbxm" (как модель)

	ChildPage = 200,           -- сколько детей показывать за раз при раскрытии
	SearchBudget = 60000,      -- сколько объектов обойти при поиске, максимум
	SearchMax = 250,           -- максимум результатов поиска
	CountBudget = 5000,        -- бюджет подсчёта объектов в выбранной ветке

	Debug = false,             -- true -> отладочные принты в консоль (F9)
	SafeFont = false,          -- true, если вместо букв квадратики (шрифт без кириллицы)
}

-- Корневые сервисы, которые показываются в дереве
local CANDIDATE_SERVICES = {
	"Workspace", "Lighting", "ReplicatedFirst", "ReplicatedStorage", "StarterGui",
	"StarterPack", "StarterPlayer", "Players", "Teams", "SoundService",
	"TextChatService", "Chat", "LocalizationService", "MaterialService",
	"ServerScriptService", "ServerStorage", "JointsService", "TestService",
	"InsertService", "PhysicsService", "ProximityPromptService", "VoiceChatService",
	"CoreGui", "CorePackages",
}

-- Пустые на клиенте (не репликуются)
local SERVER_ONLY = {
	ServerStorage = true,
	ServerScriptService = true,
}

-- Эти сервисы Studio может не принять как корень place-файла
local BAD_AS_ROOT = {
	CoreGui = true,
	CorePackages = true,
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

-- при явном FilePath USSI перезаписывает файл, поэтому имя делаем уникальным
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

-- обход поддерева без GetDescendants(): не создаём гигантскую таблицу
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

--==================================================================
-- 3. UI-ТУЛКИТ
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

-- кнопка: возвращает { frame, label, hit }
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
-- 4. ДЕРЕВО: МОДЕЛЬ УЗЛОВ
--==================================================================
local S = {
	format = CONFIG.DefaultFormat,
	busy = false,
	cancelled = false,
	searching = false,
	query = "",
	pickCount = 0,
	exclCount = 0,
	estCount = nil,
	estTruncated = false,
	countToken = 0,
	searchToken = 0,
}

local Tree = {
	byInst = {},
	roots = {},
	all = {},
}

local UI = {
	picked = 0,
}

local scheduleEstimate -- объявим ниже (используется из onToggle)

local function makeNode(inst, parentNode)
	local node = {
		inst = inst,
		name = inst.Name,
		class = inst.ClassName,
		parent = parentNode,
		depth = parentNode and (parentNode.depth + 1) or 1,
		flag = nil, -- nil | true (выбран) | false (исключён)
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

local function onToggle(node)
	if node.isMore or not node.inst then
		return
	end
	if effectiveFlag(node) then
		local parentSelected = node.parent and effectiveFlag(node.parent) or false
		-- если ветка внутри выбранного родителя — это исключение, иначе просто снятие
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

--==================================================================
-- 5. ОЦЕНКА КОЛИЧЕСТВА ВЫБРАННОГО (в фоне)
--==================================================================
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
	task.delay(0.35, function()
		if S.countToken ~= token then
			return
		end
		local picks = topPicks()
		local total, truncated = 0, false
		for _, node in ipairs(picks) do
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
-- 6. СТРОКИ ДЕРЕВА
--==================================================================
local ROW_H = 26
local ROW_GAP = 3
local INDENT = 14

local function rowX(depth)
	return 6 + (depth - 1) * INDENT
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
			TextSize = 12,
			TextColor3 = P.accent,
			Position = UDim2.new(0, x + 36, 0, 0),
			Size = UDim2.new(1, -(x + 46), 1, 0),
		})
		local hit = new("TextButton", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 1, 0),
			Text = "",
			AutoButtonColor = false,
		}, frame)
		hit.MouseButton1Click:Connect(function()
			node.parent.limit = node.parent.limit + CONFIG.ChildPage
			UI.render()
		end)
		refs.hit = hit
		node.row = refs
		return refs
	end

	-- стрелка раскрытия
	local arrowBtn = new("TextButton", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Text = "",
		Size = UDim2.new(0, 16, 0, 16),
		Position = UDim2.new(0, x, 0.5, -8),
		AutoButtonColor = false,
	}, frame)
	refs.arrowTxt = label(arrowBtn, {
		Text = "+",
		TextSize = 13,
		Font = FONT_BOLD,
		TextColor3 = P.muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, 0, 1, 0),
	})

	-- галочка
	local box = new("Frame", {
		BackgroundColor3 = P.panel2,
		BorderSizePixel = 0,
		Size = UDim2.new(0, 15, 0, 15),
		Position = UDim2.new(0, x + 20, 0.5, -7.5),
	}, frame)
	corner(box, 4)
	stroke(box, P.line, 1, 0.3)
	refs.box = box

	refs.mark = new("Frame", {
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		Size = UDim2.new(0, 7, 0, 7),
		Position = UDim2.new(0.5, -3.5, 0.5, -3.5),
	}, box)
	corner(refs.mark, 2)

	refs.half = new("Frame", {
		BackgroundColor3 = Color3.fromRGB(255, 255, 255),
		BorderSizePixel = 0,
		Size = UDim2.new(0, 7, 0, 3),
		Position = UDim2.new(0.5, -3.5, 0.5, -1.5),
	}, box)
	corner(refs.half, 1)

	refs.nameLbl = label(frame, {
		Text = node.name,
		TextSize = 12,
		Position = UDim2.new(0, x + 42, 0, 0),
		Size = UDim2.new(1, -(x + 190), 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	refs.classLbl = label(frame, {
		Text = node.class,
		TextSize = 10,
		TextColor3 = P.muted,
		TextXAlignment = Enum.TextXAlignment.Right,
		Position = UDim2.new(1, -154, 0, 0),
		Size = UDim2.new(0, 148, 1, 0),
		TextTruncate = Enum.TextTruncate.AtEnd,
	})

	-- клик по строке = отметка
	local hit = new("TextButton", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Size = UDim2.new(1, 0, 1, 0),
		Text = "",
		AutoButtonColor = false,
	}, frame)
	refs.hit = hit
	hit.MouseEnter:Connect(function()
		if effectiveFlag(node) then
			frame.BackgroundColor3 = P.rowSel
		else
			frame.BackgroundColor3 = P.panel2
		end
	end)
	hit.MouseLeave:Connect(function()
		frame.BackgroundColor3 = effectiveFlag(node) and P.rowSel or P.row
	end)
	hit.MouseButton1Click:Connect(function()
		if S.busy then
			return
		end
		onToggle(node)
	end)

	-- клик по стрелке = раскрыть/свернуть (создаётся после, поэтому ловит клик первым)
	arrowBtn.MouseButton1Click:Connect(function()
		if S.busy then
			return
		end
		UI.toggleExpand(node)
	end)

	node.row = refs
	return refs
end

--==================================================================
-- 7. ОКНО, СПИСОК, РЕНДЕР
--==================================================================
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

	local viewport = Vector2.new(1280, 720)
	local cam = workspace.CurrentCamera
	if cam then
		viewport = cam.ViewportSize
	end

	local W = math.clamp(viewport.X - 60, 420, 660)
	local H = math.clamp(viewport.Y - 60, 520, 780)
	local PAD = 14
	local HEAD_H = 46
	local TOOL_H = 32
	local PANEL_H = 172
	local BTN_H = 44
	local STATUS_H = 16

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
		Text = "USSI Object Picker",
		Font = FONT_BOLD,
		TextSize = 17,
		Position = UDim2.new(0, PAD, 0, PAD),
		Size = UDim2.new(1, -(PAD * 2) - 40, 0, 20),
	})
	label(win, {
		Text = "Раскрой сервис, отметь нужные объекты — сохранится только выбранное",
		TextSize = 12,
		TextColor3 = P.muted,
		Position = UDim2.new(0, PAD, 0, PAD + 22),
		Size = UDim2.new(1, -(PAD * 2) - 40, 0, 16),
		TextTruncate = Enum.TextTruncate.AtEnd,
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

	-- ---------- поиск + кнопки ----------
	local toolY = PAD + HEAD_H + 4

	local search = new("TextBox", {
		BackgroundColor3 = P.panel2,
		BorderSizePixel = 0,
		ClearTextOnFocus = false,
		Font = FONT,
		PlaceholderText = "поиск объекта по имени или классу...",
		PlaceholderColor3 = P.muted,
		Text = "",
		TextColor3 = P.text,
		TextSize = 12,
		TextXAlignment = Enum.TextXAlignment.Left,
		Size = UDim2.new(1, -PAD * 2 - 240, 0, TOOL_H),
		Position = UDim2.new(0, PAD, 0, toolY),
	}, win)
	corner(search, 6)
	new("UIPadding", { PaddingLeft = UDim.new(0, 8) }, search)

	button(win, {
		text = "Свернуть всё",
		size = UDim2.new(0, 116, 0, TOOL_H),
		position = UDim2.new(1, -PAD - 116 - 6 - 100, 0, toolY),
		textSize = 12,
		onClick = function()
			UI.collapseAll()
		end,
	})
	button(win, {
		text = "Сброс",
		size = UDim2.new(0, 100, 0, TOOL_H),
		position = UDim2.new(1, -PAD - 100, 0, toolY),
		textSize = 12,
		onClick = function()
			UI.clearSelection()
		end,
	})

	-- ---------- дерево ----------
	local listY = toolY + TOOL_H + 8
	local panelY = H - PAD - STATUS_H - 4 - BTN_H - 6 - PANEL_H
	local listH = math.max(120, panelY - 10 - listY)

	UI.list = new("ScrollingFrame", {
		BackgroundColor3 = P.panel,
		BorderSizePixel = 0,
		Position = UDim2.new(0, PAD, 0, listY),
		Size = UDim2.new(1, -PAD * 2, 0, listH),
		CanvasSize = UDim2.new(0, 0, 0, 0),
		ScrollBarThickness = 5,
		ScrollBarImageColor3 = P.accent,
		ScrollingDirection = Enum.ScrollingDirection.Y,
	}, win)
	corner(UI.list, 8)
	new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4) }, UI.list)
	new("UIListLayout", {
		Padding = UDim.new(0, ROW_GAP),
		SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = Enum.HorizontalAlignment.Center,
	}, UI.list)

	UI.empty = label(UI.list, {
		Text = "Сканирую сервисы…",
		TextSize = 12,
		TextColor3 = P.muted,
		TextXAlignment = Enum.TextXAlignment.Center,
		Size = UDim2.new(1, -20, 0, 30),
		LayoutOrder = -1,
	})

	-- ---------- нижняя панель ----------
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
	segmented(panel, { ".rbxl как карта", ".rbxm как модель" }, S.format == "rbxl" and 1 or 2, UDim2.new(0, 92, 0, 14), 124, function(_, value)
		S.format = (value == ".rbxl как карта") and "rbxl" or "rbxm"
		UI.updateStats()
	end)

	local panelW = W - PAD * 2
	local toggleX = math.clamp(panelW - 274, 230, 320)
	local toggleW = math.max(150, panelW - toggleX - 14)

	UI.helpLbl = label(panel, {
		Text = ".rbxl — карта с сохранением путей (File → Open from File).\n"
			.. ".rbxm — просто объекты (File → Insert from File).\n"
			.. "ServerStorage / ServerScriptService придут пустыми.",
		TextSize = 11,
		TextColor3 = P.muted,
		TextWrapped = true,
		TextYAlignment = Enum.TextYAlignment.Top,
		Position = UDim2.new(0, 14, 0, 56),
		Size = UDim2.new(0, math.max(150, toggleX - 26), 0, 100),
	})

	UI.getDecompile = toggle(panel, "Декомпилировать скрипты (Decompile)", true, UDim2.new(0, toggleX, 0, 14), toggleW)
	UI.getBytecode = toggle(panel, "Сохранять байткод (SaveBytecode)", false, UDim2.new(0, toggleX, 0, 40), toggleW)
	UI.getReadme = toggle(panel, "ReadMe-скрипт с заметками", true, UDim2.new(0, toggleX, 0, 66), toggleW)
	UI.getNil = toggle(panel, "NilInstances (объекты без родителя)", false, UDim2.new(0, toggleX, 0, 92), toggleW)
	UI.getSafe = toggle(panel, "SafeMode (кикнет перед сохранением)", false, UDim2.new(0, toggleX, 0, 118), toggleW)

	-- ---------- статус + кнопка ----------
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

	-- ---------- модалка ----------
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
		Size = UDim2.new(0, math.min(460, W - 40), 0, 280),
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
		size = UDim2.new(0, 170, 0, 36),
		position = UDim2.new(1, -186, 1, -50),
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
		position = UDim2.new(1, -304, 1, -50),
		onClick = function()
			modalHolder.Visible = false
		end,
	})
	okBtn.frame.ZIndex = 21
	okBtn.label.ZIndex = 21
	okBtn.hit.ZIndex = 22
	cancelBtn.frame.ZIndex = 21
	cancelBtn.label.ZIndex = 21
	cancelBtn.hit.ZIndex = 22

	UI.confirm = function(title, text, onConfirm)
		modalTitle.Text = title or "Подтверждение"
		modalText.Text = text or ""
		UI.onConfirm = onConfirm
		modalHolder.Visible = true
	end

	return gui
end

--==================================================================
-- 8. РЕНДЕР / РАСКРЫТИЕ / ВЫДЕЛЕНИЕ
--==================================================================
function UI.refreshNode(node)
	local refs = node.row
	if not refs or node.isMore then
		return
	end
	local selected = effectiveFlag(node)
	local excluded = node.flag == false
	local partial = (not selected) and node.trueBelow > 0

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
	refs.nameLbl.TextColor3 = selected and P.text or (excluded and P.muted or P.text)
	refs.arrowTxt.Text = node.expanded and "−" or ((node.loaded and #node.children == 0) and "" or "+")

	local info = node.class
	if node.hasChildren and node.expanded and #node.children > node.limit then
		info = node.class .. " · " .. #node.children .. " детей"
	end
	refs.classLbl.Text = info
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
		node.hasChildren = #node.children > 0
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
	if not node.inst then
		return
	end
	if not node.expanded then
		loadChildren(node)
		node.expanded = true
		if #node.children == 0 then
			UI.setStatus(node.name .. " — пусто на клиенте", P.muted)
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
	S.pickCount, S.exclCount, S.estCount = 0, 0, nil
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
	local est = estLabel()
	local mode = (S.format == "rbxl") and "карта с путями" or "модель"
	UI.setStatus(string.format(
		"выбрано: %d, исключено: %d, объектов ≈ %s · режим: %s",
		S.pickCount, S.exclCount, est, mode
	))
	UI.exportBtn.label.Text = S.pickCount > 0 and ("ЭКСПОРТИРОВАТЬ (" .. S.pickCount .. ")") or "ЭКСПОРТИРОВАТЬ"
end

--==================================================================
-- 9. ПОИСК
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

local function showResults(query, matches)
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
			Size = UDim2.new(0, 15, 0, 15),
			Position = UDim2.new(0, 10, 0.5, -7.5),
		}, frame)
		corner(box, 4)
		local mark = new("Frame", {
			BackgroundColor3 = Color3.fromRGB(255, 255, 255),
			BorderSizePixel = 0,
			Size = UDim2.new(0, 7, 0, 7),
			Position = UDim2.new(0.5, -3.5, 0.5, -3.5),
		}, box)
		corner(mark, 2)

		label(frame, {
			Text = node.name,
			TextSize = 12,
			Position = UDim2.new(0, 32, 0, 0),
			Size = UDim2.new(0, 200, 1, 0),
			TextTruncate = Enum.TextTruncate.AtEnd,
		})
		local pathLbl = label(frame, {
			Text = node.class .. " · " .. pathToString(node.inst, true),
			TextSize = 10,
			TextColor3 = P.muted,
			TextXAlignment = Enum.TextXAlignment.Right,
			Position = UDim2.new(1, -250, 0, 0),
			Size = UDim2.new(0, 244, 1, 0),
			TextTruncate = Enum.TextTruncate.AtStart,
		})

		local hit = new("TextButton", {
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Size = UDim2.new(1, 0, 1, 0),
			Text = "",
			AutoButtonColor = false,
		}, frame)
		hit.MouseButton1Click:Connect(function()
			if S.busy then
				return
			end
			if effectiveFlag(node) then
				local parentSelected = node.parent and effectiveFlag(node.parent) or false
				setFlag(node, parentSelected and false or nil)
			else
				setFlag(node, true)
			end
			mark.Visible = effectiveFlag(node)
			box.BackgroundColor3 = effectiveFlag(node) and P.accent or P.panel2
			UI.refreshAncestors(node)
			UI.updateStats()
			scheduleEstimate()
		end)

		mark.Visible = effectiveFlag(node)
		box.BackgroundColor3 = effectiveFlag(node) and P.accent or P.panel2

		local ref = { frame = frame, mark = mark, box = box }
		UI.resultRows[#UI.resultRows + 1] = ref
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
		local budget = CONFIG.SearchBudget
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
				if visited % 300 == 0 then
					task.wait()
					UI.setStatus(string.format("поиск: обошёл %d объектов, найдено %d", visited, #matches))
				end
				if visited > budget or #matches >= CONFIG.SearchMax then
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
		showResults(query, matches)
		UI.setStatus(string.format("найдено: %d (обойдено %d)", #matches, visited), #matches > 0 and P.ok or P.warn)
	end)
end

--==================================================================
-- 10. ЭКСПОРТ
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
	debugLog("USSI загружен, размер:", #source)
	return fn
end

-- строим план: что будет корнями и какие ветки отрезаем
local function buildPlan(picks)
	local keepSet = {}
	local keepList = {}

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
		-- корни = сервисы, в которых есть наш выбор
		for _, n in ipairs(keepList) do
			if n.inst.Parent == game then
				roots[#roots + 1] = n.inst
			end
		end
		-- если что-то выбрано вне сервиса (редкость) — берём сам объект
		for _, node in ipairs(picks) do
			local hasServiceAncestor = false
			local n = node
			while n do
				if n.inst.Parent == game then
					hasServiceAncestor = true
					break
				end
				n = n.parent
			end
			if not hasServiceAncestor then
				roots[#roots + 1] = node.inst
			end
		end
	else
		-- корни = сами выбранные объекты (без тех, у кого выбран родитель)
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

	-- всё, что не ведёт к выбору, помечаем игнорируемым
	local ignore, ignoreCount = {}, 0
	for _, n in ipairs(keepList) do
		local ok, kids = pcall(function()
			return n.inst:GetChildren()
		end)
		if ok then
			for _, child in ipairs(kids) do
				if not keepSet[child] then
					ignore[child] = true
					ignoreCount = ignoreCount + 1
				end
			end
		end
	end

	return roots, ignore, keepList, ignoreCount
end

local function runExport(roots, ignore)
	local genv = getGenv()
	local ext = (S.format == "rbxm") and ".rbxm" or ".rbxl"

	local base
	if #roots == 1 then
		base = sanitizeName(roots[1].Name)
	else
		base = "Selected_" .. #roots .. "_items"
	end
	local path = uniquePath(CONFIG.OutFolder, base, ext)
	genv[path] = nil -- сбросить защиту USSI от повторного сохранения того же пути

	local result = { ok = false, size = nil, err = nil }

	local options = {
		mode = "selected", -- неизвестный режим => только ExtraInstances
		ExtraInstances = roots,
		IsModel = (S.format == "rbxm"),
		IgnoreList = ignore,
		DecompileIgnore = {},

		Binary = true,
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
		ShowStatus = false,
		__DEBUG_MODE = CONFIG.Debug,

		FilePath = path,
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
	result.path = path
	return result
end

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
		Size = UDim2.new(0, 480, 0, 320),
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
		TextTruncate = Enum.TextTruncate.AtEnd,
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

	local actionBtn = button(panel, {
		text = "Отмена",
		size = UDim2.new(0, 130, 0, 36),
		position = UDim2.new(1, -146, 1, -52),
		onClick = function()
			if S.busy then
				ov.addLog("Прервать текущее сохранение нельзя: USSI уже собирает файл.", P.warn)
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

-- наш собственный интерфейс может попасть в дамп, если он внутри выбранных веток
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
	if not USSI then
		UI.setStatus("USSI ещё не загружен — подожди пару секунд", P.warn)
		return
	end
	if not CAP.writefile then
		UI.setStatus("Экзекьютор без writefile — файлы сохранить некуда", P.bad)
		notify("Object Picker", "Нужен экзекьютор с writefile", 8)
		return
	end

	local picks = topPicks()
	if #picks == 0 then
		UI.setStatus("Ничего не отмечено — поставь галочки в дереве", P.warn)
		return
	end

	local names, serviceNames, badRoots = {}, {}, {}
	for i, node in ipairs(picks) do
		if i <= 8 then
			names[#names + 1] = pathToString(node.inst, true)
		end
		local top = node.inst
		while top and top.Parent ~= game do
			top = top.Parent
		end
		if top and not serviceNames[top.Name] then
			serviceNames[top.Name] = true
			if SERVER_ONLY[top.Name] then
				table.insert(badRoots, top.Name .. " (пусто: не репликуется)")
			elseif BAD_AS_ROOT[top.Name] then
				table.insert(badRoots, top.Name .. " (Studio может не принять как корень)")
			end
		end
	end

	local listText = table.concat(names, "\n")
	if #picks > 8 then
		listText = listText .. "\n… и ещё " .. (#picks - 8)
	end

	local text = string.format(
		"Веток: %d · объектов ≈ %s\nРежим: %s\n\n%s",
		#picks,
		estLabel(),
		(S.format == "rbxl") and ".rbxl — карта, пути сохраняются" or ".rbxm — только объекты списком",
		listText
	)
	if #badRoots > 0 then
		text = text .. "\n\nВнимание: " .. table.concat(badRoots, "; ")
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
	S.cancelled = false

	local hideGui = picksTouchOwnGui(topPicks())
	local guiParent = UI.gui.Parent
	if hideGui then
		UI.gui.Parent = nil
	end

	local ov = createOverlay()
	ov.addLog("Папка: " .. CONFIG.OutFolder .. "/", P.text)
	ov.addLog(string.format("Корней: %d, отрезанных веток: %d", #roots, ignoreCount or 0), P.muted)
	if hideGui then
		ov.addLog("Окно скрипта скрыто на время дампа.", P.warn)
	end

	if CAP.makefolder then
		pcall(makefolder, CONFIG.OutFolder)
	end

	ov.setProgress(0.15)
	ov.setJob("USSI собирает только выбранные ветки…")
	ov.actionBtn.label.Text = "Идёт сохранение…"
	ov.addLog("▶ сохранение", P.text)

	local result = runExport(roots, ignore)
	ov.setProgress(1)

	if result.ok then
		ov.addLog(string.format("✓ готово — %s (%s)", result.path, fmtSize(result.size)), P.ok)
		ov.finish(string.format("Готово: %s", fmtSize(result.size)), P.ok)
	else
		ov.addLog("✗ ошибка — " .. tostring(result.err), P.bad)
		ov.finish("Не получилось", P.bad)
	end
	ov.addLog("Файлы лежат в workspace/" .. CONFIG.OutFolder .. "/ (у экзекьютора).", P.muted)

	if hideGui and guiParent then
		UI.gui.Parent = guiParent
	end

	S.busy = false
	S.cancelled = false
	UI.updateStats()
end

--==================================================================
-- 11. СТАРТ
--==================================================================
local function buildTree()
	UI.setStatus("Сканирую сервисы…")
	local found = 0
	for _, name in ipairs(CANDIDATE_SERVICES) do
		local inst = resolveService(name)
		if inst then
			local node = Tree.byInst[inst] or makeNode(inst, nil)
			node.parent = nil
			node.depth = 1
			Tree.roots[#Tree.roots + 1] = node
			found = found + 1
		end
		task.wait()
	end
	UI.render()
	return found
end

local function main()
	if type(CAP.loader) ~= "function" then
		error("экзекьютор без loadstring/load — USSI не запустить")
	end

	buildPicker()
	UI.updateStats()
	UI.gui.Enabled = true

	-- кнопка поиска живёт в потоке TextBox
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
			S.query = query
			if pending then
				pcall(task.cancel, pending)
				pending = nil
			end
			if #query < 2 then
				clearResultRows()
				UI.render()
				UI.setStatus("поиск выключен", P.muted)
				return
			end
			pending = task.delay(0.35, function()
				runSearch(query)
			end)
		end)
	end

	-- дерево строим сразу (USSI нужен только в момент экспорта)
	task.spawn(function()
		local okTree, treeErr = pcall(buildTree)
		if not okTree then
			UI.setStatus("Ошибка сканирования: " .. tostring(treeErr), P.bad)
			return
		end
		UI.setStatus("Готово. Раскрой сервис («+») и отметь нужные объекты.", P.muted)

		local okLoad, loadErr = pcall(function()
			USSI = loadUSSI()
		end)
		if not okLoad then
			UI.setStatus("Дерево готово, но USSI не загрузился: " .. tostring(loadErr), P.bad)
			notify("Object Picker", "Не смог загрузить USSI. Детали — в консоли (F9).", 10)
		else
			debugLog("USSI готов")
		end
	end)
end

local started, startErr = pcall(main)
if not started then
	warn("[ObjectPicker] " .. tostring(startErr))
	notify("Object Picker", "Ошибка запуска: " .. tostring(startErr), 10)
end

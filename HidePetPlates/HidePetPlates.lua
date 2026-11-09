local ADDON = ...
local WorldFrame = WorldFrame
local select, pairs, type = select, pairs, type
local gsub, lower = string.gsub, string.lower

local DEFAULTS = {
    copias     = true,
    serpientes = true,
    entes      = false,
    lobos      = false,
}

local db = {}
for k, v in pairs(DEFAULTS) do db[k] = v end

local function CargarAjustes()
    if type(HidePetPlatesDB) ~= "table" then HidePetPlatesDB = {} end
    for k, v in pairs(DEFAULTS) do
        if HidePetPlatesDB[k] == nil then HidePetPlatesDB[k] = v end
    end
    db = HidePetPlatesDB
end

local ACENTOS = {
    ["\195\161"]="a", ["\195\160"]="a", ["\195\164"]="a", ["\195\162"]="a",
    ["\195\169"]="e", ["\195\168"]="e", ["\195\171"]="e", ["\195\170"]="e",
    ["\195\173"]="i", ["\195\172"]="i", ["\195\175"]="i", ["\195\174"]="i",
    ["\195\179"]="o", ["\195\178"]="o", ["\195\182"]="o", ["\195\180"]="o",
    ["\195\186"]="u", ["\195\185"]="u", ["\195\188"]="u", ["\195\187"]="u",
    ["\195\177"]="n", ["\195\167"]="c",
    ["\195\129"]="a", ["\195\137"]="e", ["\195\141"]="i",
    ["\195\147"]="o", ["\195\154"]="u", ["\195\145"]="n",
}

local function Normalizar(nombre)
    if type(nombre) ~= "string" then return nil end
    nombre = gsub(nombre, "[\194-\244][\128-\191]", function(c)
        return ACENTOS[c] or c
    end)
    return lower(nombre)
end

local function Tabla(...)
    local t = {}
    for i = 1, select("#", ...) do
        local n = Normalizar((select(i, ...)))
        if n then t[n] = true end
    end
    return t
end

local SERPIENTES = Tabla(
    "Viper", "Venomous Snake",
    "Vibora", "V\195\173bora",
    "Culebra venenosa", "Serpiente venenosa",
    "Vipere", "Serpent venimeux",
    "Giftschlange",
    "Cobra venenosa",
    "Гадюка", "Ядовитая змея")

local ENTES = Tabla(
    "Treant",
    "Ente",
    "Tr\195\169ant",
    "Древень")

local LOBOS = Tabla(
    "Spirit Wolf",
    "Lobo espiritual", "Lobo esp\195\173ritu",
    "Loup spirituel",
    "Geisterwolf",
    "Призрачный волк", "Дух волка")

local COPIAS_POR_NOMBRE = Tabla(
    "Mirror Image", "Imagen especular", "Imagen de espejo",
    "Image miroir", "Spiegelbild",
    "Зеркальное изображение")

local plates = {}
local flagged = {}

local function BuscarBarra(f)
    if not f.GetNumChildren then return nil end
    for i = 1, f:GetNumChildren() do
        local h = select(i, f:GetChildren())
        if h and h.GetObjectType and h:GetObjectType() == "StatusBar"
           and h.GetStatusBarColor then
            return h
        end
    end
end

local function IsNamePlate(f)
    if not f.GetName or f:GetName() then return false end

    local region = select(2, f:GetRegions())
    if region and region.GetObjectType and region:GetObjectType() == "Texture"
       and region.GetTexture
       and region:GetTexture() == "Interface\\Tooltips\\Nameplate-Border" then
        return true
    end

    local texto = select(7, f:GetRegions())
    return (BuscarBarra(f) and texto and texto.GetText) and true or false
end

local function ScanPlates()
    for i = 1, WorldFrame:GetNumChildren() do
        local f = select(i, WorldFrame:GetChildren())
        if f and not plates[f] and IsNamePlate(f) then
            plates[f] = true
        end
    end
end

local function GetPlateName(plate)
    local region = select(7, plate:GetRegions())
    return region and region.GetText and region:GetText()
end

local function BarraDeVida(plate)
    if plate.hppBarra then return plate.hppBarra end
    plate.hppBarra = BuscarBarra(plate)
    return plate.hppBarra
end

local function EsJugador(plate)
    local barra = BarraDeVida(plate)
    if not barra then return nil end
    local r, g, b = barra:GetStatusBarColor()
    if not r then return nil end

    if r < .01 and b < .01 and g > .99 then return false end
    if r < .01 and b > .99 and g < .01 then return true  end
    if r > .99 and b < .01 and g > .99 then return false end
    if r > .99 and b < .01 and g < .01 then return false end
    return true
end

local MEMORIA = 35
local recientes, hayJugador, hayNPC = {}, {}, {}

local function Evaluate()
    local ahora = GetTime()
    for k in pairs(hayJugador) do hayJugador[k] = nil end
    for k in pairs(hayNPC) do hayNPC[k] = nil end

    for plate in pairs(plates) do
        if plate:IsShown() then
            local nombre = GetPlateName(plate)
            if nombre then
                if EsJugador(plate) then hayJugador[nombre] = true
                else hayNPC[nombre] = true end
            end
        end
    end

    for nombre in pairs(hayJugador) do
        if hayNPC[nombre] then recientes[nombre] = ahora end
    end
    for nombre, t in pairs(recientes) do
        if ahora - t > MEMORIA then recientes[nombre] = nil end
    end

    for plate in pairs(plates) do
        local ocultar = false
        if plate:IsShown() then
            local nombre = GetPlateName(plate)
            if nombre then
                local n = Normalizar(nombre)
                if db.serpientes and SERPIENTES[n] then
                    ocultar = true
                elseif db.entes and ENTES[n] then
                    ocultar = true
                elseif db.lobos and LOBOS[n] then
                    ocultar = true
                elseif db.copias then
                    if COPIAS_POR_NOMBRE[n] then
                        ocultar = true
                    elseif not EsJugador(plate)
                       and (hayJugador[nombre] or recientes[nombre]) then
                        ocultar = true
                    end
                end
            end
        end
        flagged[plate] = ocultar
    end
end

local function AlphaDeTodo(plate, a)
    plate:SetAlpha(a)
    for i = 1, plate:GetNumChildren() do
        local h = select(i, plate:GetChildren())
        if h and h.SetAlpha then h:SetAlpha(a) end
    end
    local regiones = { plate:GetRegions() }
    for i = 1, #regiones do
        local r = regiones[i]
        if r and r.SetAlpha then r:SetAlpha(a) end
    end
end

local function SetHidden(plate, hide)
    if hide then
        plate.hppHidden = true
        AlphaDeTodo(plate, 0)
    elseif plate.hppHidden then
        plate.hppHidden = nil
        plate.hppNombre = nil
        AlphaDeTodo(plate, 1)
    end
end

local function AsegurarColoresDeClase()
    local v = GetCVar("ShowClassColorInNameplate")
    if v ~= nil and v ~= "1" then
        SetCVar("ShowClassColorInNameplate", "1")
    end
end

local menu

local function CrearCasilla(padre, nombreGlobal, texto, clave, y)
    local cb = CreateFrame("CheckButton", nombreGlobal, padre, "UICheckButtonTemplate")
    cb:SetPoint("TOPLEFT", padre, "TOPLEFT", 16, y)
    local etiqueta = _G[nombreGlobal .. "Text"]
    if etiqueta then
        etiqueta:SetText(texto)
        etiqueta:SetFontObject(GameFontHighlight)
    end
    cb:SetScript("OnShow", function(self) self:SetChecked(db[clave]) end)
    cb:SetScript("OnClick", function(self)
        db[clave] = self:GetChecked() and true or false

        Evaluate()
    end)
    return cb
end

local function CrearMenu()
    local f = CreateFrame("Frame", "HidePetPlatesMenu", UIParent)
    f:SetWidth(320)
    f:SetHeight(210)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetBackdrop({
        bgFile   = "Interface\\Tooltips\\UI-Tooltip-Background",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = true, tileSize = 16, edgeSize = 16,
        insets = {left = 5, right = 5, top = 5, bottom = 5},
    })
    f:SetBackdropColor(0.028, 0.048, 0.095, 0.97)
    f:SetBackdropBorderColor(0.22, 0.52, 0.92, 0.95)
    f:EnableMouse(true)
    f:SetMovable(true)
    f:SetClampedToScreen(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()

    tinsert(UISpecialFrames, "HidePetPlatesMenu")

    local titulo = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    titulo:SetPoint("TOP", f, "TOP", 0, -14)
    titulo:SetText("|cffffffffHide|r|cff00ff00PetPlates|r")

    local cerrar = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    cerrar:SetPoint("TOPRIGHT", f, "TOPRIGHT", -2, -2)

    CrearCasilla(f, "HidePetPlatesCBCopias",
        "Hide Mage Mirror Images", "copias", -46)
    CrearCasilla(f, "HidePetPlatesCBSerpientes",
        "Hide Hunter Snake Trap snakes", "serpientes", -78)
    CrearCasilla(f, "HidePetPlatesCBEntes",
        "Hide Druid Treants", "entes", -110)
    CrearCasilla(f, "HidePetPlatesCBLobos",
        "Hide Shaman Spirit Wolves", "lobos", -142)

    return f
end

SLASH_HIDEPETPLATES1 = "/hpp"
SlashCmdList["HIDEPETPLATES"] = function()
    if not menu then menu = CrearMenu() end
    if menu:IsShown() then menu:Hide() else menu:Show() end
end

local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == ADDON then
        CargarAjustes()
        self:UnregisterEvent("ADDON_LOADED")
    elseif event == "PLAYER_LOGIN" then
        AsegurarColoresDeClase()
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)

local t1, t2 = 0, 0
local bucle = CreateFrame("Frame")
bucle:SetScript("OnUpdate", function(_, elapsed)
    t1, t2 = t1 + elapsed, t2 + elapsed
    if t2 > 0.5 then t2 = 0; ScanPlates() end
    if t1 > 0.1 then t1 = 0; Evaluate() end

    for plate, hide in pairs(flagged) do
        if hide and plate:IsShown() then

            local nombre = GetPlateName(plate)
            if plate.hppNombre and nombre ~= plate.hppNombre then
                flagged[plate] = false
                SetHidden(plate, false)
            else
                plate.hppNombre = nombre
                SetHidden(plate, true)
            end
        else
            SetHidden(plate, false)
        end
    end
end)

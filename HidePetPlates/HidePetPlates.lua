-- HidePetPlates - WoW 3.3.5a
-- Oculta las placas de:
--   * Imagenes Espejo del mago (llevan el NOMBRE DEL MAGO, no "Mirror Image")
--   * Viboras / Culebras venenosas de la Trampa de Serpientes del cazador
--
-- /hpp abre el menu para elegir que se oculta.

local ADDON = ...
local WorldFrame = WorldFrame
local select, pairs, type = select, pairs, type
local gsub, lower = string.gsub, string.lower

-- =========================================================
-- Ajustes guardados
--
-- WoW carga las SavedVariables DESPUES de ejecutar este archivo, asi que los
-- valores por defecto se completan en ADDON_LOADED. Si se hiciera aqui con
-- "HidePetPlatesDB = HidePetPlatesDB or {...}", la carga posterior pisaria
-- la tabla y se perderian.
-- =========================================================
local DEFAULTS = {
    copias     = true,   -- Imagenes Espejo del mago
    serpientes = true,   -- serpientes de la Trampa de Serpientes
    entes      = false,  -- Treants del druida (Fuerza de la naturaleza)
    lobos      = false,  -- Spirit Wolves del chaman (Espiritu feral)
}

local db = {}
for k, v in pairs(DEFAULTS) do db[k] = v end   -- hasta que llegue lo guardado

local function CargarAjustes()
    if type(HidePetPlatesDB) ~= "table" then HidePetPlatesDB = {} end
    for k, v in pairs(DEFAULTS) do
        if HidePetPlatesDB[k] == nil then HidePetPlatesDB[k] = v end
    end
    db = HidePetPlatesDB
end

-- =========================================================
-- Nombres
--
-- El cliente devuelve el nombre YA TRADUCIDO, asi que hacen falta los de cada
-- idioma. Se normaliza antes de comparar (minusculas y vocales sin tilde),
-- porque string.lower de Lua 5.1 solo toca ASCII.
-- =========================================================
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

-- Separadas, porque cada grupo va con su casilla.
local SERPIENTES = Tabla(
    "Viper", "Venomous Snake",                   -- enUS
    "Vibora", "V\195\173bora",                   -- esES / esMX
    "Culebra venenosa", "Serpiente venenosa",
    "Vipere", "Serpent venimeux",                -- frFR
    "Giftschlange",                              -- deDE
    "Cobra venenosa",                            -- ptBR
    "Гадюка", "Ядовитая змея")                   -- ruRU

-- Treants del druida. Por nombre: son tres criaturas con el mismo nombre y
-- ninguna lleva el de un jugador, asi que la regla de las copias no las toca.
local ENTES = Tabla(
    "Treant",                                    -- enUS / deDE
    "Ente",                                      -- esES / esMX
    "Tr\195\169ant",                              -- frFR
    "Древень")                                   -- ruRU

-- Spirit Wolves del chaman, mismo caso.
local LOBOS = Tabla(
    "Spirit Wolf",                               -- enUS
    "Lobo espiritual", "Lobo esp\195\173ritu",    -- esES / esMX
    "Loup spirituel",                            -- frFR
    "Geisterwolf",                               -- deDE
    "Призрачный волк", "Дух волка")              -- ruRU

-- Por si algun servidor nombra asi a las copias del mago.
local COPIAS_POR_NOMBRE = Tabla(
    "Mirror Image", "Imagen especular", "Imagen de espejo",
    "Image miroir", "Spiegelbild",
    "Зеркальное изображение")                    -- ruRU

local plates = {}
local flagged = {}

-- ---------------------------------------------------------
-- Reconocer una placa
-- ---------------------------------------------------------
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

-- Metodo clasico (textura del borde) y, de respaldo, marco sin nombre con
-- barra de vida y texto: si un parche cambiara la textura, el addon no se
-- quedaria sin reconocer ninguna placa.
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

-- =========================================================
-- JUGADOR o NPC, con la logica de Nidhaus_Plates
-- (PlatesCore.lua, GetUnitReaction): del color de la barra.
--   verde / amarillo / rojo puros -> NPC
--   azul puro o cualquier otro    -> jugador (color de clase)
-- =========================================================
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

-- =========================================================
-- Que se oculta
--
-- Serpientes: por nombre.
-- Copias del mago: placa NPC cuyo nombre es TAMBIEN el de un jugador, en
-- pantalla ahora o visto con sus copias hace menos de 35 s (la Imagen Espejo
-- dura 30). Asi no se tocan grupos de NPCs iguales (treants, lobos del
-- chaman, necrofagos) y una copia no reaparece cuando el mago sale de vista.
-- Nunca se mira arena1, target ni ninguna otra unidad.
-- =========================================================
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

-- =========================================================
-- Como se oculta
--
-- Cada fotograma, y pieza por pieza: el juego repone el alpha del marco de la
-- placa, pero no el de cada barra y cada texto por separado.
-- =========================================================
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

-- =========================================================
-- Colores de clase en las placas
--
-- Sin ellos el mago tambien sale en rojo puro y no se le puede distinguir de
-- sus copias. Se encienden al entrar; si el cliente no tiene esa variable no
-- se toca nada.
-- =========================================================
local function AsegurarColoresDeClase()
    local v = GetCVar("ShowClassColorInNameplate")
    if v ~= nil and v ~= "1" then
        SetCVar("ShowClassColorInNameplate", "1")
    end
end

-- =========================================================
-- Menu
-- =========================================================
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
        -- Se aplica al momento: lo que deja de estar marcado vuelve a verse
        -- en el siguiente fotograma, sin /reload.
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
    -- Escape lo cierra, como cualquier ventana del juego.
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

-- =========================================================
-- Arranque y bucle
-- =========================================================
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
            -- El juego recicla las placas: si el nombre cambio entre dos
            -- evaluaciones, se destapa en el acto.
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

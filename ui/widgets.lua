--[[ CC_RSMP - ui/widgets.lua
  Composants UI réutilisables pour le rendu sur monitor (ou tout objet term-like).
  Le hit-testing est pur (testable hors-jeu) ; le rendu écrit sur la cible fournie.
]]
local Widgets = {}

--- Teste si (x,y) tombe dans un bouton. @return table|nil le bouton touché.
function Widgets.hitTest(buttons, x, y)
  for _, b in ipairs(buttons) do
    if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then
      return b
    end
  end
  return nil
end

--- Dessine du texte à une position.
function Widgets.text(t, x, y, str, fg, bg)
  if bg then t.setBackgroundColor(bg) end
  if fg then t.setTextColor(fg) end
  t.setCursorPos(x, y)
  t.write(str)
end

--- Dessine un bouton rectangulaire avec label centré.
function Widgets.drawButton(t, btn, active)
  t.setBackgroundColor(active and (btn.activeBg or colors.green) or (btn.bg or colors.gray))
  t.setTextColor(btn.fg or colors.white)
  for dy = 0, btn.h - 1 do
    t.setCursorPos(btn.x, btn.y + dy)
    t.write(string.rep(" ", btn.w))
  end
  local lx = btn.x + math.max(0, math.floor((btn.w - #btn.label) / 2))
  local ly = btn.y + math.floor((btn.h - 1) / 2)
  t.setCursorPos(lx, ly)
  t.write(btn.label)
  t.setBackgroundColor(colors.black)
end

--- Dessine une barre horizontale remplie à `frac` (0..1).
function Widgets.hbar(t, x, y, w, frac, fillColor, emptyColor)
  frac = math.max(0, math.min(1, frac or 0))
  local n = math.floor(frac * w + 0.5)
  t.setCursorPos(x, y)
  t.setBackgroundColor(fillColor or colors.lime)
  t.write(string.rep(" ", n))
  t.setBackgroundColor(emptyColor or colors.gray)
  t.write(string.rep(" ", w - n))
  t.setBackgroundColor(colors.black)
end

--- Construit une rangée de boutons répartis sur la largeur `w`.
-- @param items liste de { id, label, bg? }
-- @return table de boutons { id, label, x, y, w, h, bg }
function Widgets.buttonRow(items, w, y, h, gap)
  gap = gap or 1
  local nn = #items
  local bw = math.max(3, math.floor((w - (nn + 1) * gap) / nn))
  local btns, x = {}, gap + 1
  for i, it in ipairs(items) do
    btns[i] = { id = it.id, label = it.label, x = x, y = y, w = bw, h = h, bg = it.bg }
    x = x + bw + gap
  end
  return btns
end

return Widgets

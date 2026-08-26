# Submaps Example для HyprWin

Submaps позволяют создавать многоуровневые биндинги, как в vim или i3wm.

## Пример использования:

```lua
-- Обычные биндинги в default submap
hl.bind("SUPER + R", function()
    hl.submap("resize")  -- Переключаемся в режим resize
end)

-- Биндинги для режима resize
hl.submap("resize")
hl.bind("H", function()
    -- Уменьшить ширину окна
    local ratio = HyprWin.workspace_ratios[HyprWin.current_workspace] or 0.5
    HyprWin.workspace_ratios[HyprWin.current_workspace] = math.max(0.15, ratio - 0.05)
    HyprWin.retile()
end)

hl.bind("L", function()
    -- Увеличить ширину окна
    local ratio = HyprWin.workspace_ratios[HyprWin.current_workspace] or 0.5
    HyprWin.workspace_ratios[HyprWin.current_workspace] = math.min(0.85, ratio + 0.05)
    HyprWin.retile()
end)

hl.bind("Escape", function()
    hl.submap("default")  -- Возврат в default режим
end)

-- Возвращаемся в default submap для остальных биндов
hl.submap("default")
```

## Использование:

1. **SUPER + R** - Входим в resize режим
2. **H/L** - Изменяем размер окон (работает только в resize режиме)
3. **Escape** - Выходим из resize режима

Это позволяет иметь один ключ для множества действий в зависимости от текущего режима!

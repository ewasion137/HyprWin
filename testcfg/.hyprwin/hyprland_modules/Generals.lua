HyprWin.apps = {
    { name = "Visual Studio Code", path = "code" },
    { name = "Telegram",          path = "telegram.exe" },
    { name = "Spotify",           path = "spotify.exe" },
    { name = "Terminal (Kitty)",  path = "kitty.exe" },
    { name = "--- System ---",    path = "cmd.exe" },
    { name = "Power Off",         path = "shutdown /s /t 0" }
}

hl.bind("ALT + S", function() 
    require("control_center").toggle() 
end)

hl.config({
  general = {
    gaps_in  = 5,
    gaps_out = 10,
    border_size = 2,

    col = {
      active_border   = "rgba(ffffffff)",
      inactive_border = "rgba(00000000)",
    },

    resize_on_border = true,
    allow_tearing = false,
    layout = "dwindle",

    snap = {
      enabled = true,
      respect_gaps = false
    }
  },
})

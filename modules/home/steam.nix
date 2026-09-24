# Steam opens its Friends List window on every client start since the 2023 UI rewrite, even with
# the window closed at last exit, and has no setting to stop it short of disabling "Sign in to
# Friends when Steam Client starts". This closes only the first Friends List window each Steam
# process maps, so friends sign-in stays on and opening the list by hand later still works.
{ ... }:
{
  krane.hypr.extraGeneralLua = ''
    local steam_friends_closed = {}
    local function close_steam_startup_friends(w)
      if w and w.class == "steam" and w.title == "Friends List" and not steam_friends_closed[w.pid] then
        steam_friends_closed[w.pid] = true
        hl.dispatch(hl.dsp.window.close({ window = "address:" .. w.address }))
      end
    end
    -- window.title too: Steam can map the window before it sets the final title.
    hl.on("window.open", close_steam_startup_friends)
    hl.on("window.title", close_steam_startup_friends)
  '';
}

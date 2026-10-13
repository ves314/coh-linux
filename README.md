# City of Heroes on your own PC

This kit runs a private City of Heroes server on your Windows PC, so you can play solo.
It uses a Linux port of the Ouroboros servers (version v2i2.1.0), packaged for Docker
Desktop. Only the game on the same PC can connect; nothing is opened to your network.

The game data and the game client are **not** included. You get them from Ouroboros.

## What you need

- Windows 10 or 11, 64-bit, with an Intel or AMD processor. 16 GB of memory is
  recommended, and about 15 GB of free disk space.
- [Docker Desktop](https://www.docker.com/products/docker-desktop/), free for personal
  use. Install it, start it once and accept its terms. The installer may ask you to restart.
- The Ouroboros **Volume 2 Issue 1.1 (v2i2.1.0)** server files and game client. Ouroboros
  shares them on its GitLab, [git.ourodev.com](https://git.ourodev.com/users/sign_in), which
  needs an account. You need the server data, the server piggs and the matching client. Other
  versions will not work with these servers.

## Play

1. Download this repository as a ZIP (the green **Code** button, then **Download ZIP**) and
   extract it, for example to `C:\Games\coh-kit`.
2. Double-click **start.bat**. If Windows warns that the file came from the internet,
   choose **Run** (or **More info**, then **Run anyway**).
3. The first time, it asks for:
   - the Ouroboros **Server** folder (the one with `data`, `piggs` and `version.ini`),
   - the **client** folder (the one with `Ouroboros.exe`),
   - an account name and password for the game.

   It then copies about 9 GB of game data into Docker, which takes a few minutes.
4. When it says **Ready**, press Enter to start the game and log in with your account.

Next time, double-click **City of Heroes (local)** on your desktop, or start.bat.

## Stop

Run **stop.bat**, or the **Stop City of Heroes servers** shortcut. It saves every
character first, then stops the servers. Quitting Docker Desktop without it can lose the
last few seconds of play.

## Update to a new version

Download the new ZIP and extract it **over your existing kit folder**, replacing the files.
Your settings (`.env` and `settings.json`) are kept, and so are your accounts and characters,
which live in Docker. Then run start.bat as usual; it loads the new server image.

## Start over

**reset.bat** deletes the servers, the copy of the game data, and every account and
character. Your Ouroboros folders are not touched. Run start.bat afterwards to set up again.

## Good to know

- Each zone or mission you are in runs its own map server, using about 1 GB of memory.
  Ones nobody is in shut down after 5 minutes.
- Account names are not case-sensitive.
- To add another account while the servers run, open PowerShell in this folder and run
  `powershell -ExecutionPolicy Bypass -File scripts\coh.ps1 account`.
- Known gaps: NPCs and pets in supergroup bases only follow you along clear straight lines
  (no pathing beacons for bases), as on the Ouroboros Windows release.

## Troubleshooting

- **Docker Desktop is not running, or uses Windows containers.** Open Docker Desktop and
  wait until it shows "Engine running". If it is set to Windows containers, right-click its
  icon near the clock and choose **Switch to Linux containers**.
- **Creating your first character says the account server is not running.** This can
  happen in the first seconds after an account is created. Wait a moment and try again.
- **The servers stop while starting.** Run start.bat again. If it keeps happening, open
  PowerShell and run `docker logs coh-local-game-1`; the lines starting with `[coh` say
  which server failed.
- **Ports in use.** The servers need TCP port 2106 and UDP ports 7000 to 7060 on this PC.
  Stop any other City of Heroes server first.

## Credits

This is a hobby project, made for fun to test the capabilities of AI. It is not an official
release.

The servers are the Ouroboros project's City of Heroes server code, ported to Linux.
City of Heroes was made by Cryptic Studios and Paragon Studios and published by NCsoft.
This kit is not affiliated with, endorsed or supported by any of them.

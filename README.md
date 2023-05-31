Run this to setup: ```Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process -Force; .\setup.ps1```
It changes policy, because windows is weird and makes it hard to execute scripts, it reverts after window is closed.

Post install, most stuff is set up, you might need to click accept on some stuff, but mostly not.
At the end of script you need to login into steam to download shit.

Run lunarvim with ```lvim```
even though it runs it just do ```:Lazy sync```, should say after it prompts you to accept a bunch of stuff

you can do ```:LvimSyncCorePlugins``` to sync applications and ```:LvimUpdate``` to update.

to run outside just use ```lvim +LvimUpdate +q``` for example

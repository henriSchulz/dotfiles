-- Extra autostart processes.
-- o.launch_on_start("my-service")

-- Close gaps between workspaces when one runs empty.
o.launch_on_start("hypr-workspace-compact")

-- EasyEffects: speaker preset for the XPS 13 (autoloaded on the speakers).
o.launch_on_start("easyeffects-service")

-- Screenshots land in ~/Pictures/Screenshot instead of ~/Pictures.
hl.env("OMARCHY_SCREENSHOT_DIR", os.getenv("HOME") .. "/Pictures/Screenshot")

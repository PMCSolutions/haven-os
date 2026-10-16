// Haven OS - classic taskbar (Windows 10 style)
// [Start] [pinned + open apps .................] [tray] [clock] [show desktop]

var panel = new Panel;
panel.location = "bottom";
panel.height = 2 * Math.ceil(gridUnit * 2.4 / 2);
try { panel.floating = false; } catch (e) { /* older Plasma */ }

var start = panel.addWidget("org.kde.plasma.kickoff");
start.currentConfigGroup = ["General"];
start.writeConfig("icon", "haven-start");
start.currentConfigGroup = ["Shortcuts"];
start.writeConfig("global", "Alt+F1");

var tasks = panel.addWidget("org.kde.plasma.icontasks");
tasks.currentConfigGroup = ["General"];
tasks.writeConfig("launchers",
    "applications:org.kde.dolphin.desktop," +
    "applications:firefox.desktop," +
    "applications:steam.desktop," +
    "applications:org.kde.discover.desktop," +
    "applications:systemsettings.desktop");
tasks.writeConfig("groupingStrategy", 1);
tasks.writeConfig("middleClickAction", "NewInstance");

panel.addWidget("org.kde.plasma.marginsseparator");
panel.addWidget("org.kde.plasma.systemtray");

var clock = panel.addWidget("org.kde.plasma.digitalclock");
clock.currentConfigGroup = ["Appearance"];
clock.writeConfig("showDate", true);
clock.writeConfig("dateDisplayFormat", "BelowTime");

panel.addWidget("org.kde.plasma.showdesktop");

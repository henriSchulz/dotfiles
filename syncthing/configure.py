#!/usr/bin/env python3
"""Cable-only Syncthing config. Usage: syncthing-configure.py OWN_IP PEER_NAME PEER_ID PEER_IP"""
import os, sys, xml.etree.ElementTree as ET

own_ip, peer_name, peer_id, peer_ip = sys.argv[1:5]
home = os.path.expanduser("~")
path = os.path.join(home, ".local/state/syncthing/config.xml")
tree = ET.parse(path)
root = tree.getroot()
own_id = root.find("device").get("id")  # generate writes this device first

opts = root.find("options")
def opt(name, value):
    for e in opts.findall(name):
        opts.remove(e)
    for v in (value if isinstance(value, list) else [value]):
        ET.SubElement(opts, name).text = v

opt("listenAddress", f"tcp://{own_ip}:22000")
opt("globalAnnounceServer", [])
opt("globalAnnounceEnabled", "false")
opt("localAnnounceEnabled", "false")
opt("relaysEnabled", "false")
opt("natEnabled", "false")
opt("stunServer", [])
opt("stunKeepaliveStartS", "0")
opt("urAccepted", "-1")
opt("urURL", "")
opt("crashReportingEnabled", "false")
opt("crashReportingURL", "")
opt("autoUpgradeIntervalH", "0")
opt("releasesURL", "")
opt("startBrowser", "false")
opt("announceLANAddresses", "false")

gui = root.find("gui")
gui.find("address").text = "127.0.0.1:8384"

# devices: own + peer only
for d in root.findall("device"):
    if d.get("id") != own_id:
        root.remove(d)
own = root.find("device")
own.set("name", os.uname().nodename)
peer = ET.Element("device", {"id": peer_id, "name": peer_name, "compression": "metadata",
                             "introducer": "false", "skipIntroductionRemovals": "false",
                             "introducedBy": ""})
ET.SubElement(peer, "address").text = f"tcp://{peer_ip}:22000"
ET.SubElement(peer, "paused").text = "false"
ET.SubElement(peer, "autoAcceptFolders").text = "false"
root.insert(list(root).index(own) + 1, peer)

# folders: exactly ours
for f in root.findall("folder"):
    root.remove(f)
for fid, rel in [("documents", "Documents"), ("uni", "Uni"), ("work", "Work"), ("pictures", "Pictures")]:
    f = ET.Element("folder", {"id": fid, "label": rel, "path": os.path.join(home, rel), "type": "sendreceive",
                              "rescanIntervalS": "3600", "fsWatcherEnabled": "true", "fsWatcherDelayS": "10",
                              "ignorePerms": "false", "autoNormalize": "true"})
    for dev in (own_id, peer_id):
        ET.SubElement(f, "device", {"id": dev, "introducedBy": ""})
    v = ET.SubElement(f, "versioning", {"type": "trashcan"})
    ET.SubElement(v, "param", {"key": "cleanoutDays", "val": "30"})
    ET.SubElement(v, "cleanupIntervalS").text = "3600"
    ET.SubElement(f, "minDiskFree", {"unit": "%"}).text = "1"
    ET.SubElement(f, "markerName").text = ".stfolder"
    root.insert(list(root).index(root.find("device")), f)

ET.indent(tree, "    ")
tree.write(path, encoding="utf-8", xml_declaration=False)
print(f"{own_id} -> {peer_name} {peer_id} @ {peer_ip}")

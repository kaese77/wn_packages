-- Copyright 2015 Andreas Bräu <ab@andi95.de> 
-- Licensed to the public under the Apache License 2.0.                                     
                                                                                
local fs = require "nixio.fs"
local util = require "luci.util"
local uci = require "luci.model.uci".cursor()
local profiles = "/etc/config/profile_*"

m = Map("ffwizard", translate("Einstellungen fürs Weimarnetz"))
w = m:section(NamedSection, "settings", "node", nil, translate("Allgemein"))
s = m:section(TypedSection, "wifi", nil, translate("SSIDs"))
v = m:section(NamedSection, "vpn", "vpn", nil, translate("VPN"))

publishEmail = w:option(Flag, "email2owm", translate("Email veröffentlichen"), translate("Soll deine Emailadresse auf unserem <a href=\"http://weimarnetz.de/monitoring\" target=\"_blank\">Monitoring</a> erscheinen? Die Adresse ist dort öffentlich einsehbar. Bei Problemen kann man dich kontaktieren. Sonst ist die Adresse nur auf deinem Router sichtbar."))
publishEmail.rmempty=false
publishEmail.default='0'

restrict = w:option(Flag, "restrict", translate("LAN-Zugriff unterbinden"), translate("Soll Zugriff auf das eigene lokale Netzwerk blockiert werden?"))
restrict.rmempty=false 

vpnMode = v:option(ListValue, "enable", translate("VPN-Modus"), translate("Wie soll VPN genutzt werden?"))
vpnMode:value("off", translate("VPN deaktivieren"))
vpnMode:value("on", translate("VPN aktivieren und Internetverkehr darüber leiten"))
vpnMode:value("innercity", translate("VPN aktivieren, nur zur Verbindung mit der Wolke"))
vpnNoInternet = v:option(Flag, "disableinternet", translate("Kein Internet bei VPN-Ausfall"), translate("Soll der Internetzugang für WLAN-Nutzer gesperrt werden, wenn VPN ausfällt?"))
vpnNoInternet.rmempty=false
vpnNoInternet.default='0'
vpnNoInternet:depends("enable", "1")
btn = v:option(Button, "_btn", translate("VPN-Änderungen anwenden"))
function btn.write()
    luci.sys.call(". /tmp/loader && _vpn restart")
end

ssid = s:option(Value, "ap_ssid", translate("SSID"), translate("SSID für das öffentlich zugängliche Netzwerk")) 
function ssid:validate(value)
	if value:len()<=32 and value:match("[0-9A-Za-z\ -\(\)]") then
		return value
	else
		return false
	end
end

return m


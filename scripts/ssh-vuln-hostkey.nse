local shortport = require "shortport"
local ssh2 = require "ssh2"
local ssh1 = require "ssh1"
local stdnse = require "stdnse"

local io = require "io"
local string = require "string"
local table = require "table"

description = [[
Checks if ssh server has a predictable hostkey by checking it against a list of fingerprints 
generated by HD Moore. You have to download these hostkeys separately and specify their directory
as the fingerprintdir variable. The keys are available at http://itsecurity.net/debian_ssh_scan_v4.tar.bz2. Additionally, you can specify a file ssh hostkey fingerprints, one per line, and the scripts will report if the hostkey matches one of the provided fingerprints.  
]]

---
-- @usage 
-- nmap -p 22 --script ssh-vuln-hostkey \
--    --script-args fingerprintdir=<directory with vulnerable fingerprints> <target>
--
-- @output
-- 
-- 22/tcp   open   ssh     syn-ack
-- | ssh-vuln-hostkey: 
-- |   Weak hostkeys: 
-- |_    2048 6d:cd:2a:8b:dc:3e:e0:92:00:47:59:16:8c:8b:17:70 (RSA)
--
--
-- @usage
-- -- nmap -p 22 --script ssh-vuln-hostkey \
--    --script-args fingerprintfile=<file with fingerprints to check for> <target>
--
-- @output
--
-- 22/tcp open  ssh     syn-ack
-- | ssh-vuln-hostkey: 
-- |   Listed hostkeys: 
-- |_    2048 6d:cd:2a:8b:dc:3e:e0:92:00:47:59:16:8c:8b:17:70 (RSA)
--
-- @args fingerprintdir   Directory containing vulnerable fingerprints
-- @args fingerprintfile  File containing fingerprints to check against
--

author = "Devin Bjelland"

license = "Same as Nmap--See http://nmap.org/book/man-legal.html"
categories = {"safe","default","discovery"}

dependencies = {"ssh-hostkey"}

portrule = shortport.port_or_service(22, 'ssh')

local fingerprintdir = stdnse.get_script_args("fingerprintdir") 
local fingerprintfile = stdnse.get_script_args("fingerprintfile")

action = function (host, port)
  local key
  local keys = {}
  local r = stdnse.output_table()
  local w = {}
  local listed_hostkeys = {}
  local found_listed_key
  local found_weak_key

  if nmap.registry.sshhostkey and nmap.registry.sshhostkey[host.ip] then
    keys = nmap.registgry.sshhostkey[host.ip]
  else
    key = ssh2.fetch_host_key( host, port, "ssh-rsa" )
    if key then table.insert( keys, key ) end

    key = ssh2.fetch_host_key( host, port, "ssh-dss" )
    if key then table.insert( keys, key ) end
  end

  for _,key in ipairs(keys) do
      local fingerprint = stdnse.tohex(key.fingerprint)
      stdnse.debug("fingerprint: " .. fingerprint) 
      if fingerprintdir then
        if key.key_type == "ssh-rsa" then
          for line in io.lines(fingerprintdir .. "ssh_rsa_" .. key.bits .. "_keys.txt") do
            local stripped_line = string.gsub(line, "-.*", "")
            if stripped_line == fingerprint then
              found_weak_key = true
              stdnse.verbose("Found weak hostkey: " .. ssh1.fingerprint_hex(key.fingerprint, key.algorithm, key.bits))
              table.insert(w, ssh1.fingerprint_hex(key.fingerprint, key.algorithm, key.bits))
            end         
          end
        elseif key.key_type == "ssh-dss" and key.bits == "1024" then
          for line in io.lines(fingerprintdir .. "ssh_dsa_1024_keys.txt", "r") do 
            local stripped_line = string.gsub(line, "-.*", "")
            if stripped_line == fingerprint then
              found_weak_key = true
              stdnse.verbose("Found weak hostkey: " .. ssh1.fingerprint_hex(key.fingerprint, key.algorithm, key.bits))
              table.insert(w, ssh1.fingerprint_hex(key.fingerprint, key.algorithm, key.bits))
            end
          end
        end
      end
      if fingerprintfile then
        for line in io.lines(fingerprintfile) do
          local stripped_line = string.gsub(line, ":", "")
          if stripped_line == fingerprint then
            found_listed_key = true
            table.insert(listed_hostkeys, ssh1.fingerprint_hex(key.fingerprint, key.algorithm, key.bits))
            stdnse.verbose("Found hostkey on list:" .. ssh1.fingerprint_hex(key.fingerprint, key.algorithm, key.bits))
          end
        end
      end
  end

  if not found_weak_key then
    w = "No weak hostkeys found"
  end
  
  if not found_listed_key then
    list_hostkey = "No listed hostkeys found"
  end
  
  if fingerprintdir then
    r["Weak hostkeys"] = w 
  end

  if fingerprintfile then
    r["Listed hostkeys"] = listed_hostkeys
  end

  return r
end
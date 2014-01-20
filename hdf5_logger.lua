#!/usr/bin/luajit

--[[
ffi = require("ffi")
ubx = require "ubx"
time = require("time")
ubx_utils = require("ubx_utils")
ts = tostring
hdf5 = require "hdf5"
--array = require "array"

-- prog starts here.

--print(hdf5.get_libversion())

function dosomething(x,y,z)
  print ("X is "..x.." and y is "..y.." and z is "..z)
end

print("creating array")
local buf = ffi.new("double[3]",10.01, 11.11, 12.21)

print("creating file")
local file = hdf5.create_file("Testfile1.h5")

print("creating space")
local space = hdf5.create_simple_space({1,3})

print("creating group")
local group = file:create_group("Testgroup1")

print("creating dataset")
local dataset = group:create_dataset("TestDataset1", hdf5.double, space)

print("write data from buffer to dataset")
dataset:write(buf,hdf5.double)

print("closing file")
file:flush_file()

--io.read()
]]--

--- Original code of file logger --> already edited a bit

local ubx=require("ubx")
local ubx_utils = require("ubx_utils")
local utils = require("utils")
local cdata = require("cdata")
local ffi = require("ffi")
local time = require("time")
local ts = tostring
local strict = require"strict"
local hdf5 = require"array"

-- global state
filename=nil
file=nil
group=nil
tot_conf
fd=nil

-- sample_conf={
--    { blockname='blockA', portname="port1", buff_len=10, },
--    { blockname='blockB', portname=true, buff_len=10 }, -- report all
--}

-- sample_conf={
--    { blockname='youbot1', portname="base_msr_twist", buff_len=1, port_var="vel.x", dataset_name="/LinearVelocity/x", dataset_type="double", group_name="/State/Twist"},
--    { blockname='youbot1', portname="base_msr_twist", buff_len=1, port_var="vel.y", dataset_name="/LinearVelocity/y", dataset_type="double", group_name="/State/Twist"},
--    { blockname='youbot1', portname="base_msr_twist", buff_len=1, port_var="vel.z", dataset_name="/LinearVelocity/z", dataset_type="double", group_name="/State/Twist"},
--    { blockname='youbot1', portname="base_msr_twist", buff_len=1, port_var="rot.x", dataset_name="/LinearVelocity/x", dataset_type="double", group_name="/State/Twist"},
--    { blockname='youbot1', portname="base_msr_twist", buff_len=1, port_var="rot.y", dataset_name="/LinearVelocity/y", dataset_type="double", group_name="/State/Twist"},
--    { blockname='youbot1', portname="base_msr_twist", buff_len=1, port_var="rot.z", dataset_name="/LinearVelocity/z", dataset_type="double", group_name="/State/Twist"},
-- }

local ts1=ffi.new("struct ubx_timespec")
local ns_per_s = 1000000000

function get_time()
   ubx.clock_mono_gettime(ts1)
   return tonumber(ts1.sec) + tonumber(ts1.nsec) / ns_per_s
end

--- For the given port, create a ubx_data to hold the result of a read.
-- @param port
-- @return ubx_data_t sample
function create_read_sample(p, ni)
   return ubx.data_alloc(ni, p.out_type_name, p.out_data_len)
end

--- convert the conf string to a table.
-- @param conf str
-- @param ni node_info
-- @return tot_conf table
local function conf_to_tot_conflist(c, this)
   local ni = this.ni
   
   local succ, res = utils.eval_sandbox("return "..c)
   if not succ then error("hdf5_logger: failed to load conf:\n"..res) end

   for i,conf in ipairs(res) do
      local bname, pname, dsname, dstype, gname = ts(conf.blockname), ts(conf.port_name
      --- TODO implement here!

--- convert the port_conf string to a table.
-- @param port_conf str
-- @param ni node_info
-- @return pconf table with inv. conn. ports
local function port_conf_to_portlist(pc, this)
   local ni = this.ni

   local succ, res = utils.eval_sandbox("return "..pc)
   if not succ then error("file_logger: failed to load port_conf:\n"..res) end

   for i,conf in ipairs(res) do
      local bname, pname = ts(conf.blockname), ts(conf.portname)

      local b = ubx.block_get(ni, bname)
      if b==nil then
	 print("file_logger error: no block "..bname.." found")
	 return false
      end
      local p = ubx.port_get(b, pname)
      if p==nil then
	 print("file_logger error: block "..bname.." has no port "..pname)
	 return false
      end

      if conf.buff_len==nil or conf.buff_len <=0 then
	 conf.buff_len=1
      end

      if p.out_type~=nil then
	 local blockport = bname.."."..pname
	 local p_rep_name=ts(i)
	 print("file_logger: reporting "..blockport.." as "..p_rep_name)
	 ubx.port_add(this, p_rep_name, nil, p.out_type_name, p.out_data_len, nil, 0, 0)
	 ubx.conn_lfds_cyclic(b, pname, this, p_rep_name, conf.buff_len)

	 conf.pname = p_rep_name
	 conf.sample=create_read_sample(p, ni)
	 conf.sample_cdata = ubx.data_to_cdata(conf.sample)
	 conf.serfun=cdata.gen_logfun(ubx.data_to_ctype(conf.sample), blockport)
      else
	 print("ERR: file_logger: refusing to report in-port ", bname.."."..pname)
      end
   end

   -- cache port ptr's (only *after* adding has finished (realloc!)
   for _,conf in ipairs(res) do conf.pinv=ubx.port_get(this, conf.pname) end

   return res
end

--- convert the group_conf string to a table.
-- @param group_conf str
-- @param ni node_info
-- @return gconf table with groups
local function group_conf_to_grouplist(gc, this)
   local ni = this.ni

   local succ, res = utils.eval_sandbox("return "..gc)
   if not succ then error("file_logger: failed to load group_conf:\n"..res) end

   for i,conf in ipairs(res) do
      --local bname, pname = ts(conf.blockname), ts(conf.portname)
      local gname = ts(conf.groupname)
      --- TODO put groupnames in table

      local b = ubx.block_get(ni, bname)
      if b==nil then
	 print("file_logger error: no block "..bname.." found")
	 return false
      end
      local p = ubx.port_get(b, pname)
      if p==nil then
	 print("file_logger error: block "..bname.." has no port "..pname)
	 return false
      end

      if conf.buff_len==nil or conf.buff_len <=0 then
	 conf.buff_len=1
      end

      if p.out_type~=nil then
	 local blockport = bname.."."..pname
	 local p_rep_name=ts(i)
	 print("file_logger: reporting "..blockport.." as "..p_rep_name)
	 ubx.port_add(this, p_rep_name, nil, p.out_type_name, p.out_data_len, nil, 0, 0)
	 ubx.conn_lfds_cyclic(b, pname, this, p_rep_name, conf.buff_len)

	 conf.pname = p_rep_name
	 conf.sample=create_read_sample(p, ni)
	 conf.sample_cdata = ubx.data_to_cdata(conf.sample)
	 conf.serfun=cdata.gen_logfun(ubx.data_to_ctype(conf.sample), blockport)
      else
	 print("ERR: file_logger: refusing to report in-port ", bname.."."..pname)
      end
   end

   -- cache port ptr's (only *after* adding has finished (realloc!)
   for _,conf in ipairs(res) do conf.pinv=ubx.port_get(this, conf.pname) end

   return res
end

local function pvtds_to_pvtdslist(pvc, this)
   local ni = this.ni

   local succ, res = utils.eval_sandbox("return"..gc)
   if not succ then error("file_logger: failed to load group_conf:\n"..res) end

   --- TODO implement!
end

--- init: parse config and create port and connections.
function init(b)
   b=ffi.cast("ubx_block_t*", b)
   ubx.ffi_load_types(b.ni)

   --- port_conf
   local pconf_str = ubx.data_tolua(ubx.config_get_data(b, "port_conf"))

   if pconf_str == 0 then
      print(ubx.safe_tostr(b.name)..": invalid/nonexisting port_conf")
      return false
   end

   --- group_conf
   local gconf_str = ubx.data_tolua(ubx.config_get_data(b, "group_conf"))

   if gconf_str == 0 then
      print(ubx.safe_tostr(b.name)..": invalid/nonexisting group_conf")
      return false
   end

   --- port_var_to_dataset_conf
   local pvconf_str = ubx.data_tolua(ubx.config_get_data(b, "port_var_to_dataset_conf"))

   if pvconf_str == 0 then
      print(ubx.safe_tostr(b.name)..": invalid/nonexisting port_var_to_dataset_conf")
      return false
   end

   filename = ubx.data_tolua(ubx.config_get_data(b, "filename"))

   -- print(('file_logger.init: reporting to file="%s", sep="%s", conf=%s'):format(filename, separator, rconf_str))
   print(('file_logger: reporting to file="%s", sep="%s"'):format(filename, separator))

   pconf = port_conf_to_portlist(pconf_str, b)
   --- TODO add new functions for groups and portvartodataset
   gconf = group_conf_to_grouplist(gconf_str, b)
   pvconf = pvtds_to_pvtdslist(pvconf_str, b)
   return true
end

--- start: create new hdf5 file
function start(b)

   --[[
   b=ffi.cast("ubx_block_t*", b)
   ubx.ffi_load_types(b.ni)

   if timestamp~=0 then
      fd:write(("time, "):format(get_time()))
   end

   for i=1,#rconf do
      rconf[i].serfun("header", fd)
      if i<#rconf then fd:write(", ") end
   end

   fd:write("\n")
   ]]--
   print("creating file")
   file = hdf5.create_file(filename)
   return true
end

--- step: read ports and write values
function step(b)
   --[[
   b=ffi.cast("ubx_block_t*", b)

   if timestamp~=0 then
      fd:write(("%f, "):format(get_time()))
   end

   for i=1,#rconf do
      if ubx.port_read(rconf[i].pinv, rconf[i].sample) < 0 then
	 print("file_logger error: failed to read "..rconf.blockname.."."..rconf.portname)
      else
	 rconf[i].serfun(rconf[i].sample_cdata, fd)
	 if i<#rconf then fd:write(", ") end
      end
   end
   fd:write("\n")
   ]]--
   --- TODO get time (this will need to be specifiable from outside --> maybe separate block?)
   --- TODO create group according to time
   if timestamp~=0 then
      group = file:create_group(("%f, "):format(get_time()))
   end
   
   --- TODO create groups within group created according to time
   for i=1,#gconf do
      group:create_group(gconf[i])
   end
   --- TODO get data from specified ports and write to specified datasets
   ---		|-> create dataset from specific value of port given in pvconf
   ---		|-> create buffer according to data 
   ---		|-> create space according to data size
   ---		|-> get data from port to buffer
   ---		|-> write data from buffer to dataset
   for i=1,#pconf do
      if ubx.port_read(pconf[i].pinv, pconf[i].sample) < 0 then
         print("hdf5_logger error: failed to read "..pconf.blockname.."."..pconf.portname)
      else
         pconf[i].serfun(pconf[i].sample_cdata, fd)
         if i<#pconf then fd:write(", ") end
      end
   end

   for i=1,#pvconf do

   end
end

--- cleanup
function cleanup(b)
   --io.close(fd)
   print("closing file")
   file:flush_file()
   fd=nil
   filename=nil
   file=nil
   group=nil
   pconf=nil
   gconf=nil
   pvconf=nil
end

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

local ubx=require("ubx")
local ubx_utils = require("ubx_utils")
local utils = require("utils")
local cdata = require("cdata")
local ffi = require("ffi")
local time = require("time")
local ts = tostring
local strict = require"strict"
local hdf5 = require"hdf5"

-- global state
filename=nil
file=nil
timestamp=nil
group=nil
tot_conf=nil
fd=nil

-- sample_conf={
--    { blockname='blockA', portname="port1", buff_len=10, },
--    { blockname='blockB', portname=true, buff_len=10 }, -- report all
--}

-- sample_conf={
--    { blockname='youbot1', portname="base_msr_twist", buff_len=1, port_var="vel.x", dataset_name="x", dataset_type="double", group_name="/State/Twist/LinearVelocity/"},
--    { blockname='youbot1', portname="base_msr_twist", buff_len=1, port_var="vel.y", dataset_name="y", dataset_type="double", group_name="/State/Twist/LinearVelocity/"},
--    { blockname='youbot1', portname="base_msr_twist", buff_len=1, port_var="vel.z", dataset_name="z", dataset_type="double", group_name="/State/Twist/LinearVelocity/"},
--    { blockname='youbot1', portname="base_msr_twist", buff_len=1, port_var="rot.x", dataset_name="x", dataset_type="double", group_name="/State/Twist/RotationalVelocity/"},
--    { blockname='youbot1', portname="base_msr_twist", buff_len=1, port_var="rot.y", dataset_name="y", dataset_type="double", group_name="/State/Twist/RotationalVelocity/"},
--    { blockname='youbot1', portname="base_msr_twist", buff_len=1, port_var="rot.z", dataset_name="z", dataset_type="double", group_name="/State/Twist/RotationalVelocity/"},
-- }

local ts1=ffi.new("struct ubx_timespec")
local ns_per_s = 1000000000

function get_time()
   ubx.clock_mono_gettime(ts1)
   return tonumber(ts1.sec) + tonumber(ts1.nsec) / ns_per_s
end

function existsobject(f,g)
   f:exists_object(g)
end

function checkforgroup(f,g)
   if pcall(existsobject,f,g) then
      return true
   else
      return false
   end
end

function creategroups(f,gs)
   local i,j=0
   while j~=string.len(gs) do
      if i==0 then
         i=string.find(gs,"/")
      else
         i=j
      end
      j=string.find(gs,"/",i+1)
      local sub=string.sub(gs,i+1,j-1)
      --- TODO DEBUG
      print(f)
      print(sub)
      if checkforgroup(f,sub) then
      else
         f=f:create_group(sub)
      end   
   end
   return f
end

--- For the given port, create a ubx_data to hold the result of a read.
-- @param port
-- @return ubx_data_t sample
-- TODO Usefull?
function create_read_sample(p, ni)
   return ubx.data_alloc(ni, p.out_type_name, p.out_data_len)
end

--- convert the conf string to a table (save in global states and add ports).
-- @param conf str
-- @param ni node_info
-- @return tot_conf table
local function port_conf_to_conflist(c, this)
   local ni = this.ni
   
   local succ, res = utils.eval_sandbox("return "..c)
   if not succ then error("hdf5_logger: failed to load report_conf:\n"..res) end

   for i,conf in ipairs(res) do
      local bname, pname, pvar, dsname, dstype, gname = ts(conf.blockname), ts(conf.portname), ts(conf.port_var), ts(conf.dataset_name), ts(conf.dataset_type), ts(conf.group_name)
      
      --- TODO implement here!
      --- get block
      local b = ubx.block_get(ni, bname)
      if b==nil then
         print("hdf5_logger error: no block "..bname.." found")
	 return false
      end
      --- get port
      local p = ubx.port_get(b, pname)
      if p==nil then
	 print("hdf5_logger error: block "..bname.." has no port "..pname)
	 return false
      end
      --- set buffer length if not specified
      if conf.buff_len==nil or conf.buff_len <=0 then
	 conf.buff_len=1
      end
      --- add port
      if p.out_type~=nil then --- if port out type is not nil
	 local blockport = bname.."."..pname
	 local p_rep_name=ts(i)
	 print("hdf5_logger: reporting "..blockport.." as "..p_rep_name)
	 ubx.port_add(this, p_rep_name, nil, p.out_type_name, p.out_data_len, nil, 0, 0)
	 ubx.conn_lfds_cyclic(b, pname, this, p_rep_name, conf.buff_len)

	 conf.pname = p_rep_name
	 -- TODO ubx_data_t argument is nil
	 conf.sample=create_read_sample(p, ni)
	 conf.sample_cdata = ubx.data_to_cdata(conf.sample)
	 conf.serfun=cdata.gen_logfun(ubx.data_to_ctype(conf.sample), blockport)
      else
	 print("ERR: hdf5_logger: refusing to report in-port ", bname.."."..pname)
      end
   end

   -- cache port ptr's (only *after* adding has finished (realloc!)
   for _,conf in ipairs(res) do conf.pinv=ubx.port_get(this, conf.pname) end

   return res
end

--- init: parse config and create port and connections.
function init(b)
   b=ffi.cast("ubx_block_t*", b)
   ubx.ffi_load_types(b.ni)

   --- tot_conf
   local tot_conf_str = ubx.data_tolua(ubx.config_get_data(b, "report_conf"))

   if tot_conf_str == 0 then
      print(ubx.safe_tostr(b.name)..": invalid/nonexisting report_conf")
      return false
   end

   filename = ubx.data_tolua(ubx.config_get_data(b, "filename"))
   timestamp = ubx.data_tolua(ubx.config_get_data(b, "timestamp"))

   -- print(('file_logger.init: reporting to file="%s", sep="%s", conf=%s'):format(filename, separator, rconf_str))
   print(('file_logger: reporting to file="%s"'):format(filename))

   tot_conf = port_conf_to_conflist(tot_conf_str, b)
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
   --for i=1,#tot_conf.group_name do
   for i=1,#tot_conf do
      creategroups(group, tot_conf[i].group_name)
   end
   --- TODO get data from specified ports and write to specified datasets
   ---		|-> create dataset from specific value of port given in pvconf
   ---		|-> create buffer according to data 
   ---		|-> create space according to data size
   ---		|-> get data from port to buffer
   ---		|-> write data from buffer to dataset

   --- TODO Commented!
   --[[
   for i=1,#tot_conf.block_name do
      local buf = ffi.new(tot_conf.dataset_type[i],||dataFromPort||)
      local space = hdf5.create_simple_space({1,||sizeOfDataFromPort||}) --- will we have multiple dimension (3+) data?
      group = group:open_group(tot_conf.group_name[i])
      -- TODO link the dataset_type to a hdf5 set:
      --       |-> switch with mapping from double to hdf5.double ...
      local datatype = hdf5.double
      local dataset = group:create_dataset(tot_conf.dataset_name[i], datatype, space)
      dataset:write(buf,datatype)
   end
   ]]--
      
   --[[
   for i=1,#pconf do
      if ubx.port_read(pconf[i].pinv, pconf[i].sample) < 0 then
         print("hdf5_logger error: failed to read "..pconf.blockname.."."..pconf.portname)
      else
         pconf[i].serfun(pconf[i].sample_cdata, fd)
         if i<#pconf then fd:write(", ") end
      end
   end
   ]]--
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
   tot_conf=nil
end

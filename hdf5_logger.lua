#!/usr/bin/luajit

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
base_group=nil
--group=nil
tot_conf=nil

-- sample_conf={
--    { blockname='youbot1', portname="base_msr_twist", buff_len=1, port_var="vel.x", dataset_name="x", dataset_type="double", group_name="/State/Twist/LinearVelocity/"},
--    { blockname='youbot1', portname="base_msr_twist", buff_len=1, port_var="vel.y", dataset_name="y", dataset_type="double", group_name="/State/Twist/LinearVelocity/"},
--    { blockname='youbot1', portname="base_msr_twist", buff_len=1, port_var="vel.z", dataset_name="z", dataset_type="double", group_name="/State/Twist/LinearVelocity/"},
--    { blockname='youbot1', portname="base_msr_twist", buff_len=1, port_var="rot.x", dataset_name="x", dataset_type="double", group_name="/State/Twist/RotationalVelocity/"},
--    { blockname='youbot1', portname="base_msr_twist", buff_len=1, port_var="rot.y", dataset_name="y", dataset_type="double", group_name="/State/Twist/RotationalVelocity/"},
--    { blockname='youbot1', portname="base_msr_twist", buff_len=1, port_var="rot.z", dataset_name="z", dataset_type="double", group_name="/State/Twist/RotationalVelocity/"},
-- }

--sample_conf2=[[
--{
   --{ blockname='random1', portname="rnd", buff_len=1, port_var="", dataset_name="randomNumber", dataset_type="integer", group_name="/Random/Random1/" },
   --{ blockname='random1', portname="rnd", buff_len=1, port_var="", dataset_name="randomNumber2", dataset_type="integer", group_name="/Random/Random2/" }
--}
--]]


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
   local sub

   while j~=string.len(gs) do

      if i==0 then
         i=string.find(gs,"/")
      else
         i=j
      end
      j=string.find(gs,"/",i+1)
      sub=string.sub(gs,i+1,j-1)
      if checkforgroup(f,sub) then
         f=f:open_group(sub)
      else
         f=f:create_group(sub)
      end   
   end
   return f
end

--- For the given port, create a ubx_data to hold the result of a read.
-- @param port
-- @return ubx_data_t sample
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

   --- get conf
   local tot_conf_str = ubx.data_tolua(ubx.config_get_data(b, "report_conf"))

   if tot_conf_str == 0 then
      print(ubx.safe_tostr(b.name)..": invalid/nonexisting report_conf")
      return false
   end

   filename = ubx.data_tolua(ubx.config_get_data(b, "filename"))
   timestamp = ubx.data_tolua(ubx.config_get_data(b, "timestamp"))
   print(('file_logger: reporting to file="%s"'):format(filename))
   --- create tot_conf from string
   tot_conf = port_conf_to_conflist(tot_conf_str, b)
   return true
end

--- start: create new hdf5 file
function start(b)

   print("creating file")
   file = hdf5.create_file(filename)
   return true
end

--- step: read ports and write values
function step(b)

   --- TODO get time (this will need to be specifiable from outside --> maybe separate block?)
   --- create group according to time
   if timestamp~=0 then
      base_group = file:create_group(("%f, "):format(get_time()))
   end
   
   --- create groups within group created according to time
   for i=1,#tot_conf do
      --print("creating groups: "..tot_conf[i].group_name)
      local group = creategroups(base_group, tot_conf[i].group_name)
      -- create dataset inside this group
      if ubx.port_read(tot_conf[i].pinv, tot_conf[i].sample) < 0 then
         print("hdf5_logger error: failed to read"..tot_conf.blockname.."."..tot_conf.portname)
      else
         print("DATA: "..ts(tot_conf[i].sample_cdata))
         --- create c data type 
         local buf = ffi.new("int[1]") -- TODO Not hardcoded!
	 buf = tot_conf[i].sample_cdata
         local space = hdf5.create_simple_space({1,1}) -- TODO Not hardcoded!
         --local datatype = hdf5.double
         --local dataset = group:create_dataset(tot_conf[i].dataset_name, datatype, space)
         local dataset = group:create_dataset(tot_conf[i].dataset_name, hdf5.char, space)
         --dataset:write(buf, datatype)
         dataset:write(buf, hdf5.char)
      end
   end
end

--- cleanup
function cleanup(b)
   print("closing file")
   file:flush_file()
   filename=nil
   file=nil
   --group=nil
   base_group=nil
   tot_conf=nil
end

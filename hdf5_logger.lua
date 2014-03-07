--
-- Microblx hdf5 logger
--
-- SPDX-License-Identifier: BSD-3-Clause LGPL-2.1+
--

local ubx=require("ubx")
local utils = require("utils")
local cdata = require("cdata")
local ffi = require("ffi")
local time = require("time")
local ts = tostring
local hdf5 = require"hdf5"

-- color handling via ubx
red=ubx.red; blue=ubx.blue; cyan=ubx.cyan; white=ubx.cyan; green=ubx.green; yellow=ubx.yellow; magenta=ubx.magenta

-- global state
filename=nil
file=nil
timestamp=nil
tot_conf=nil

--- configuration examples
--sample_conf=[[
--{
   --{ blockname='youbot1', portname="base_msr_twist", buff_len=1, port_var="vel.x", dataset_name="x", dataset_type="double", group_name="/State/Twist/LinearVelocity/"},
   --{ blockname='youbot1', portname="base_msr_twist", buff_len=1, port_var="vel.y", dataset_name="y", dataset_type="double", group_name="/State/Twist/LinearVelocity/"},
   --{ blockname='youbot1', portname="base_msr_twist", buff_len=1, port_var="vel.z", dataset_name="z", dataset_type="double", group_name="/State/Twist/LinearVelocity/"},
   --{ blockname='youbot1', portname="base_msr_twist", buff_len=1, port_var="rot.x", dataset_name="x", dataset_type="double", group_name="/State/Twist/RotationalVelocity/"},
   --{ blockname='youbot1', portname="base_msr_twist", buff_len=1, port_var="rot.y", dataset_name="y", dataset_type="double", group_name="/State/Twist/RotationalVelocity/"},
   --{ blockname='youbot1', portname="base_msr_twist", buff_len=1, port_var="rot.z", dataset_name="z", dataset_type="double", group_name="/State/Twist/RotationalVelocity/"},
--}
--]]

--sample_conf2=[[
--{
   --{ blockname='random1', portname="rnd", buff_len=1, port_var="", dataset_name="randomNumber", dataset_type="integer", group_name="/Random/Random1/" },
   --{ blockname='random1', portname="rnd", buff_len=1, port_var="", dataset_name="randomNumber2", dataset_type="integer", group_name="/Random/Random2/" }
--}
--]]

--sample_conf3(TODO)=[[
--{
   --{ blockname='youbot1', portname="base_msr_twist", buff_len=1, port_var={"vel.x", "vel.y", "vel.z", "rot.x", "rot.y", "rot.z"}, dataset_name={"x", "y", "z", "x", "y", "z"}, group_name={"/State/Twist/LinearVelocity/", "/State/Twist/LinearVelocity/", "/State/Twist/LinearVelocity/", "/State/Twist/RotationalVelocity", "/State/Twist/RotationalVelocity", "/State/Twist/RotationalVelocity"}},
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

function getdatatypefromdatasettype(s)
   if s == "int[1]" then
      return hdf5.int
   elseif s == "long[1]" then
      return hdf5.long
   elseif s == "double[1]" then
      return hdf5.double
   end
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
local function port_conf_to_conflist(rc, this)
   local ni = this.ni
   
   local succ, res = utils.eval_sandbox("return "..rc)
   if not succ then error(red("hdf5_logger: failed to load report_conf:\n"..res, true)) end

   for i,conf in ipairs(res) do
      local bname, pname = conf.blockname, conf.portname

      local b = ni:b(bname)

      if b==nil then
	 print(red("hdf5_logger error: no block ",true)..green(bname, true)..red(" found", true))
	 return false
      end

      -- TODO Change to this implementation (copy from logger)
      -- are we directly connecting to an iblock??
      if pname==nil and ubx.is_iblock(b) then
	 print("file_logger: reporting iblock ".. ubx.safe_tostr(b.name))
	 local p_rep_name='r'..ts(i)
	 local type_name = ubx.data_tolua(ubx.config_get_data(b, "type_name"))
	 local data_len = ubx.data_tolua(ubx.config_get_data(b, "data_len"))

	 ubx.port_add(this, p_rep_name, "reporting iblock "..bname, type_name, data_len, nil, 0, 0)
	 local p = ubx.port_get(this, p_rep_name)
	 ubx.port_connect_in(p, b)

	 conf.type = 'iblock'
	 conf.bname = bname
	 conf.pname = pname
	 conf.p_rep_name = p_rep_name
	 conf.sample = ubx.data_alloc(ni, p.in_type_name, p.in_data_len)
	 conf.sample_cdata = ubx.data_to_cdata(conf.sample, true)
	 conf.serfun=cdata.gen_logfun(ubx.data_to_ctype(conf.sample, true), bname)

      else -- normal connection to cblock
         --- get port
         local p = ubx.port_get(b, pname)
         if p==nil then
            print(red("hdf5_logger error: block ", true)..green(bname, true)..red(" has no port ", true)..cyan(pname, true))
	    return false
         end
         --- set buffer length if not specified
         if conf.buff_len==nil or conf.buff_len <=0 then conf.buff_len=1 end
         --- add port
         -- TODO if port and block are the same we don't need to add it again?
         -- |-> so check for availability of combination of port and block?
         -- This will be fixed if we define in config multiple data for each port
         if p.out_type~=nil then --- if port out type is not nil
	    local blockport = bname.."."..pname
	    --local p_rep_name=ts(i)
	    local p_rep_name='r'..ts(i)
            local iblock
	    print("hdf5_logger: reporting "..blockport.." as "..p_rep_name)
	    --ubx.port_add(this, p_rep_name, nil, p.out_type_name, p.out_data_len, nil, 0, 0)
	    ubx.port_add(this, p_rep_name, "reporting "..blockport, p.out_type_name, p.out_data_len, nil, 0, 0)
	    iblock = ubx.conn_lfds_cyclic(b, pname, this, p_rep_name, conf.buff_len)

	    conf.type = 'port'
	    conf.iblock_name = iblock:get_name()
	    conf.bname = bname
	    conf.pname = p_rep_name
	    conf.p_rep_name = p_rep_name
	    conf.sample=create_read_sample(p, ni)
	    --- if conf.pvar is empty create simple cdata, else get cdata from struct by port_var
	    ----if conf.pvar == "" then
	    if conf.port_var == "" then
	    conf.sample_cdata = ubx.data_to_cdata(conf.sample)
	    else
	    local ok, fun = utils.eval_sandbox(utils.expand("return function (t) return t.$INDEX end", {INDEX=conf.port_var}))
	    conf.sample_cdata = ubx.data_to_cdata(conf.sample)
	    conf.trim_struct = fun
	    end
	    --- unused?
	    --conf.serfun=cdata.gen_logfun(ubx.data_to_ctype(conf.sample), blockport)
         else
            print(red("ERR: hdf5_logger: refusing to report in-port ", bname.."."..pname), true)
         end
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

   -- TODO get time 
   -- |-> this will need to be specifiable from outside --> maybe separate block?
   -- at the moment this is ubx.clock_mono_gettime()
   --- create group according to time
   local base_group
   if timestamp~=0 then
      base_group = file:create_group(("%f"):format(get_time()))
   else
      -- TODO if no timestamp we need to create states 
      -- |-> starting from 000000?
      base_group = file
   end
   
   --- create groups within group created according to time
   for i=1,#tot_conf do
      --print("creating groups: "..tot_conf[i].group_name)
      local group = creategroups(base_group, tot_conf[i].group_name)
      -- create dataset inside this group
      if ubx.port_read(tot_conf[i].pinv, tot_conf[i].sample) < 0 then
         print("hdf5_logger error: failed to read"..tot_conf.blockname.."."..tot_conf.portname)
      else
         --print("DATA: "..ts(tot_conf[i].sample_cdata))
	 local datatype = getdatatypefromdatasettype(tot_conf[i].dataset_type)
         local buf = ffi.new(tot_conf[i].dataset_type)

         --- if it's a struct inside the buf we need to trim it with trim_struct
	 if tot_conf[i].port_var == "" then
	    buf = tot_conf[i].sample_cdata
	 else
	    -- TODO if we need multiple parts of the struct a for loop according to port_var is needed here
	    buf = ffi.new(tot_conf[i].dataset_type, tot_conf[i].trim_struct(tot_conf[i].sample_cdata))
	 end
	 local size = ffi.sizeof(buf)/datatype:get_size()
	 --print("size: "..size)
	 -- TODO more than 1 dimension?
         local space = hdf5.create_simple_space({1,size})
         local dataset = group:create_dataset(tot_conf[i].dataset_name, datatype, space)
         dataset:write(buf, datatype)
      end
   end
end

--- cleanup
function cleanup(b)
   b=ffi.cast("ubx_block_t*", b)
   local ni = b.ni

   -- cleanup connections and remove ports
   for i,c in ipairs(tot_conf) do
      if c.type == 'iblock' then
	 ubx.port_disconnect_in(b:p(c.p_rep_name), ni:b(c.bname))
	 b:port_rm(c.p_rep_name)
      else
	 -- disconnect reporting iblock from reported port:
	 ubx.port_disconnect_out(ni:b(c.bname):p(c.pname), ni:b(c.iblock_name))
	 -- disconnect local port from iblock and remove it
	 ubx.port_disconnect_in(b:p(c.p_rep_name), ni:b(c.iblock_name))
	 b:port_rm(c.p_rep_name)
	 -- unload iblock
	 ni:block_unload(c.iblock_name)
      end
   end
   print("closing file")
   file:flush_file()
   filename=nil
   timestamp=nil
   file=nil
   tot_conf=nil
end

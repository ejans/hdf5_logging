#!/usr/bin/env luajit

local ffi = require("ffi")
local ubx = require "ubx"
local ts = tostring

ni=ubx.node_create("testnode")

ubx.load_module(ni, "std_types/stdtypes/stdtypes.so")
ubx.load_module(ni, "std_types/testtypes/testtypes.so")
ubx.load_module(ni, "std_blocks/random/random.so")
ubx.load_module(ni, "std_blocks/hexdump/hexdump.so")
ubx.load_module(ni, "std_blocks/lfds_buffers/lfds_cyclic.so")
ubx.load_module(ni, "std_blocks/webif/webif.so")
--ubx.load_module(ni, "std_blocks/logging/file_logger.so")
ubx.load_module(ni, "std_blocks/hdf5_logging/converter.so")
ubx.load_module(ni, "std_blocks/hdf5_logging/saver.so")
ubx.load_module(ni, "std_blocks/ptrig/ptrig.so")

ubx.ffi_load_types(ni)

print("creating instance of 'webif/webif'")
webif1=ubx.block_create(ni, "webif/webif", "webif1", { port="8888" })

print("creating instance of 'random/random'")
random1=ubx.block_create(ni, "random/random", "random1", {min_max_config={min=32, max=127}})

print("creating instance of 'hexdump/hexdump'")
hexdump1=ubx.block_create(ni, "hexdump/hexdump", "hexdump1")

print("creating instance of 'lfds_buffers/cyclic'")
--fifo1=ubx.block_create(ni, "lfds_buffers/cyclic", "fifo1", {element_num=4, element_size=4})
fifo1=ubx.block_create(ni, "lfds_buffers/cyclic", "fifo1", {buffer_len=4, type_name="unsigned int"})
fifo2=ubx.block_create(ni, "lfds_buffers/cyclic", "fifo2", {buffer_len=1, type_name="struct hdf5_logging_data"})

print("creating instance of 'hdf5_logging/converter'")

--[[
logger_conf=[[
{
   { blockname='random1', portname="rnd", buff_len=1, },
   { blockname='fifo1', portname="overruns", buff_len=1, },
   { blockname='ptrig1', portname="tstats", buff_len=3, }
}
]]


logger_conf=[[
{
   { blockname='random1', portname="rnd", buff_len=1, port_var="", dataset_name="randomNumber", dataset_type="int[1]", group_name="/Random/Random1/" },
   { blockname='random1', portname="rnd", buff_len=1, port_var="", dataset_name="randomNumber2", dataset_type="long[1]", group_name="/Random/Random2/" }
}
]]

-- sample_conf={
--    { blockname='youbot1', portname="base_msr_twist", buff_len=1, port_var="vel.x", dataset_name="x", dataset_type="double", group_name="/State/Twist/LinearVelocity/"},
--    { blockname='youbot1', portname="base_msr_twist", buff_len=1, port_var="vel.y", dataset_name="y", dataset_type="double", group_name="/State/Twist/LinearVelocity/"},
--    { blockname='youbot1', portname="base_msr_twist", buff_len=1, port_var="vel.z", dataset_name="z", dataset_type="double", group_name="/State/Twist/LinearVelocity/"},
--    { blockname='youbot1', portname="base_msr_twist", buff_len=1, port_var="rot.x", dataset_name="x", dataset_type="double", group_name="/State/Twist/RotationalVelocity/"},
--    { blockname='youbot1', portname="base_msr_twist", buff_len=1, port_var="rot.y", dataset_name="y", dataset_type="double", group_name="/State/Twist/RotationalVelocity/"},
--    { blockname='youbot1', portname="base_msr_twist", buff_len=1, port_var="rot.z", dataset_name="z", dataset_type="double", group_name="/State/Twist/RotationalVelocity/"},
-- }


converter1=ubx.block_create(ni, "hdf5_logging/converter", "converter1",
			   {filename=os.date("%Y%m%d_%H%M%S")..'_report.h5',
			    timestamp=1,
			    report_conf=logger_conf})

print("creating instance of 'hdf5_logging/saver'")
saver1=ubx.block_create(ni, "hdf5_logging/saver", "saver1",
			{filename=os.date("%Y%m%d_%H%M%S")..'_report.h5'})

print("creating instance of 'std_triggers/ptrig'")
ptrig1=ubx.block_create(ni, "std_triggers/ptrig", "ptrig1",
			{
			   --period = {sec=0, usec=100000 },
			   period = {sec=2, usec=0 },
			   sched_policy="SCHED_OTHER", sched_priority=0,
			   trig_blocks={ { b=random1, num_steps=1, measure=0 },
					 { b=converter1, num_steps=1, measure=0 }
			   } } )

-- ubx.ni_stat(ni)

print("running webif init", ubx.block_init(webif1))
print("running ptrig1 init", ubx.block_init(ptrig1))
print("running random1 init", ubx.block_init(random1))
print("running hexdump1 init", ubx.block_init(hexdump1))
print("running fifo1 init", ubx.block_init(fifo1))
print("running converter1 init", ubx.block_init(converter1))
print("running saver1 init", ubx.block_init(saver1))

print("running webif start", ubx.block_start(webif1))

rand_port=ubx.port_get(random1, "rnd")
converter_port=ubx.port_get(converter1, "data")
saver_port=ubx.port_get(saver1, "data")

ubx.port_connect_out(rand_port, hexdump1)
ubx.port_connect_out(rand_port, fifo1)

ubx.port_connect_out(converter_port, fifo2)
ubx.port_connect_in(saver_port, fifo2)

ubx.block_start(fifo1)
ubx.block_start(fifo2)
ubx.block_start(random1)
ubx.block_start(hexdump1)
ubx.block_start(converter1)
ubx.block_start(saver1)

--print(utils.tab2str(ubx.block_totab(random1)))
print("--- demo app launched, browse to http://localhost:8888 and start ptrig1 block to start up")
io.read()

print("stopping and cleaning up blocks --------------------------------------------------------")
print("running ptrig1 unload", ubx.block_unload(ni, "ptrig1"))
print("running webif1 unload", ubx.block_unload(ni, "webif1"))
print("running random1 unload", ubx.block_unload(ni, "random1"))
print("running fifo1 unload", ubx.block_unload(ni, "fifo1"))
print("running hexdump unload", ubx.block_unload(ni, "hexdump1"))
print("running converter1 unload", ubx.block_unload(ni, "converter1"))
print("running saver1 unload", ubx.block_unload(ni, "saver1"))

-- ubx.ni_stat(ni)
-- l1=ubx.ubx_alloc_data(ni, "unsigned long", 1)
-- if l1~=nil then print_data(l1) end

ubx.unload_modules(ni)
-- ubx.ni_stat(ni)
os.exit(1)

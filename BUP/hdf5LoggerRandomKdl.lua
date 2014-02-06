#!/usr/bin/env luajit

local ffi = require("ffi")
local ubx = require "ubx"
local ubx_utils = require("ubx_utils")
local ts = tostring

-- prog starts here.
ni=ubx.node_create("hdf5LoggerRandomKdl")

-- load modules
ubx.load_module(ni, "std_types/stdtypes/stdtypes.so")
ubx.load_module(ni, "std_types/kdl/kdl_types.so")
ubx.load_module(ni, "std_blocks/webif/webif.so")
ubx.load_module(ni, "std_blocks/youbot_driver/youbot_driver.so")
ubx.load_module(ni, "std_blocks/hdf5_logging/hdf5_logger.so")
ubx.load_module(ni, "std_blocks/lfds_buffers/lfds_cyclic.so")
ubx.load_module(ni, "std_blocks/ptrig/ptrig.so")
ubx.load_module(ni, "std_blocks/random_kdl/random_kdl.so")

ubx.ffi_load_types(ni)

-- create necessary blocks
print("creating instance of 'webif/webif'")
webif1=ubx.block_create(ni, "webif/webif", "webif1", { port="8888" })

print("creating instance of 'random_kdl/random_kdl'")
random_kdl1=ubx.block_create(ni, "random_kdl/random_kdl", "random_kdl1", {min_max_config={min=0, max=10}})

print("creating instance of 'hdf5_logging/hdf5_logger'")

--logger_conf=[[
--{
    --{ blockname='random_kdl1', portname="base_msr_twist", buff_len=1, data_type="kdl_twist", port_var="vel.x", dataset_name="x", dataset_type="double[1]", group_name="/State/Twist/LinearVelocity/"}
--}
--]]

logger_conf=[[
{
    { blockname='random_kdl1', portname="base_msr_twist", buff_len=1, port_var="vel.x", dataset_name="x", dataset_type="double[1]", group_name="/State/Twist/LinearVelocity/"}
}
]]

hdf5_log1=ubx.block_create(ni, "hdf5_logging/hdf5_logger", "hdf5_log1",
                           {filename=os.date("%Y%m%d_%H%M%S")..'_report.h5',
                            timestamp=1,
                            report_conf=logger_conf})

print("creating instance of 'std_triggers/ptrig'")
ptrig1=ubx.block_create(ni, "std_triggers/ptrig", "ptrig1", {
                period = {sec=2, usec=0},
		--sched_policy="SCHED_FIFO", sched_priority=85,
		sched_policy="SCHED_OTHER", sched_priority=0,
		trig_blocks={ { b=random_kdl1, num_steps=1, measure=0 },
		              { b=hdf5_log1, num_steps=1, measure=0} 
                } } )

print("running webif init", ubx.block_init(webif1))
print("running ptrig1 init", ubx.block_init(ptrig1))
print("running random_kdl1 init", ubx.block_init(random_kdl1))
print("running hdf5_log1 init", ubx.block_init(hdf5_log1))

print("running webif start", ubx.block_start(webif1))
--print("running ptrig1 start", ubx.block_start(ptrig1))
print("running random_kdl1 start", ubx.block_start(random_kdl1))
print("running hdf5_log1 start", ubx.block_start(hdf5_log1))


--print("initializing ptrig1")
--ubx.block_init(ptrig1)

--- Move with a given twist.
-- @param twist table.
-- @param dur duration in seconds
function move_twist(twist_tab, dur)
   --set_control_mode(2) -- VELOCITY
   ubx.data_set(twist_data, twist_tab)
   local ts_start=ffi.new("struct ubx_timespec")
   local ts_cur=ffi.new("struct ubx_timespec")

   ubx.clock_mono_gettime(ts_start)
   ubx.clock_mono_gettime(ts_cur)

   while ts_cur.sec - ts_start.sec < dur do
      ubx.port_write(p_msr_twist, twist_data)
      ubx.clock_mono_gettime(ts_cur)
   end
   ubx.port_write(p_msr_twist, null_twist_data)
end

function fill_twist()
   ubx.port_write(p_msr_twist, null_twist_data)
end

function fill_twist2()
   twist_data = ubx.port_read(i_msr_twist)
   ubx.port_write(p_msr_twist, twist_data)
end

function connect_twist()
   ubx.connect_one(i_mst_twist, hdf51)
end

io.read()

node_cleanup(ni)



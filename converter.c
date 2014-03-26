/*
 * microblx: embedded, real-time safe, reflective function blocks.
 * Copyright (C) 2013,2014 Markus Klotzbuecher <markus.klotzbuecher@mech.kuleuven.be>
 *
 * microblx is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2 or (at your option)
 * any later version.
 *
 * microblx is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with eCos; if not, write to the Free Software Foundation,
 * Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301 USA.
 *
 * As a special exception, if other files instantiate templates or use
 * macros or inline functions from this file, or you compile this file
 * and link it with other works to produce a work based on this file,
 * this file does not by itself cause the resulting work to be covered
 * by the GNU General Public License. However the source code for this
 * file must still be made available in accordance with section (3) of
 * the GNU General Public License.
 *
 * This exception does not invalidate any other reasons why a work
 * based on this file might be covered by the GNU General Public
 * License.
*/

/*
 * A generic luajit based block.
 */

/* #define DEBUG	1 */
#define COMPILE_IN_LOG_LUA_FILE

#include <luajit-2.0/lauxlib.h>
#include <luajit-2.0/lualib.h>
#include <luajit-2.0/lua.h>

#include <stdio.h>
#include <stdlib.h>

#include "ubx.h"
#include "types/hdf5_logging_data.h"
#include "types/hdf5_logging_data.h.hexarr"

#ifdef COMPILE_IN_LOG_LUA_FILE
#include "converter.lua.hexarr"
#else
#define FILE_LOG_FILE "/home/mk/prog/c/microblx/std_blocks/hdf5_logging/converter.lua"
#endif

char converter_meta[] =
	"{ doc='A block that creates an hdf5 file',"
	"  license='MIT',"
	"  real-time=false,"
	"}";

ubx_config_t converter_conf[] = {
	{ .name="report_conf", .type_name="char" },
	{ .name="filename", .type_name="char" },
	{ .name="timestamp", .type_name="int"},
	{ NULL }
};

ubx_port_t converter_ports[] = {
	{ .name="data", .attrs=PORT_DIR_OUT, .out_type_name="struct hdf5_logging_data" },
	{ NULL },
};

ubx_type_t hdf5_logging_data_type = def_struct_type(struct hdf5_logging_data, &hdf5_logging_data_h);

struct converter_info {
	struct lua_State* L;
};


/**
 * @brief: call a hook with fname.
 *
 * @param block (is passed on a first arg)
 * @param fname name of function to call
 * @param require_fun raise an error if function fname does not exist.
 * @param require_res if 1, require a boolean valued result.
 * @return -1 in case of error, 0 otherwise.
 */
int call_hook(ubx_block_t* b, const char *fname, int require_fun, int require_res)
{
	int ret = 0;
	struct converter_info* inf = (struct converter_info*) b->private_data;
	int num_res = (require_res != 0) ? 1 : 0;

	lua_getglobal(inf->L, fname);

	if(lua_isnil(inf->L, -1)) {
		lua_pop(inf->L, 1);
		if(require_fun)
			ERR("%s: no (required) Lua function %s", b->name, fname);
		goto out;
	}

	lua_pushlightuserdata(inf->L, (void*) b);

	if (lua_pcall(inf->L, 1, num_res, 0) != 0) {
		ERR("%s: error calling function %s: %s", b->name, fname, lua_tostring(inf->L, -1));
		lua_pop(inf->L, 1); /* pop result */
		ret = -1;
		goto out;
	}

	if(require_res) {
		if (!lua_isboolean(inf->L, -1)) {
			ERR("%s: %s must return a bool but returned a %s",
			    b->name, fname, lua_typename(inf->L, lua_type(inf->L, -1)));
			ret = -1;
			goto out;
		}
		ret = !(lua_toboolean(inf->L, -1)); /* back in C! */
		lua_pop(inf->L, 1); /* pop result */
	}
 out:
	return ret;
}

/**
 * init_lua_state - initalize lua_State and execute lua_file.
 *
 * @param inf
 * @param lua_file
 *
 * @return 0 if Ok, -1 otherwise.
 */
static int init_lua_state(struct converter_info* inf)
{
	int ret=-1;

	if((inf->L=luaL_newstate())==NULL) {
		ERR("failed to alloc lua_State");
		goto out;
	}

	luaL_openlibs(inf->L);

#ifdef COMPILE_IN_LOG_LUA_FILE
	ret = luaL_dostring(inf->L, (const char*) &converter_lua);
#else
	ret = luaL_dofile(inf->L, FILE_LOG_FILE);
#endif
	
	if (ret) {
		ERR("Failed to load converter.lua: %s\n", lua_tostring(inf->L, -1));
		goto out;
	}
	ret=0;

 out:
	return ret;
}


static int converter_init(ubx_block_t *b)
{
	DBG(" ");
	int ret = -EOUTOFMEM;
	struct converter_info* inf;

	if((inf = calloc(1, sizeof(struct converter_info)))==NULL)
		goto out;

	b->private_data = inf;

	if(init_lua_state(inf) != 0)
		goto out_free;

	if((ret=call_hook(b, "init", 0, 1)) != 0)
		goto out_free;

	/* Ok! */
	ret = 0;
	goto out;

 out_free:
	free(inf);
 out:
	return ret;
}

static int converter_start(ubx_block_t *b)
{
	DBG(" ");
	return call_hook(b, "start", 0, 1);
}

/**
 * converter_step - execute lua string and call step hook
 *
 * @param b
 */
static void converter_step(ubx_block_t *b)
{
	call_hook(b, "step", 0, 0);
	return;
}

static void converter_stop(ubx_block_t *b)
{
	call_hook(b, "stop", 0, 0);
}

static void converter_cleanup(ubx_block_t *b)
{
	struct converter_info* inf = (struct converter_info*) b->private_data;
	call_hook(b, "cleanup", 0, 0);
	lua_close(inf->L);
	free(b->private_data);
}


/* put everything together */
ubx_block_t lua_comp = {
	.name = "hdf5_logging/converter",
	.type = BLOCK_TYPE_COMPUTATION,
	.meta_data = converter_meta,
	.configs = converter_conf,
	.ports = converter_ports,
	/* .ports = lua_ports, */

	/* ops */
	.init = converter_init,
	.start = converter_start,
	.step = converter_step,
	.stop = converter_stop,
	.cleanup = converter_cleanup,
};

static int converter_mod_init(ubx_node_info_t* ni)
{
	ubx_type_register(ni, &hdf5_logging_data_type);
	return ubx_block_register(ni, &lua_comp);
}

static void converter_mod_cleanup(ubx_node_info_t *ni)
{
	ubx_block_unregister(ni, "hdf5_logging/converter");
}

UBX_MODULE_INIT(converter_mod_init)
UBX_MODULE_CLEANUP(converter_mod_cleanup)
UBX_MODULE_LICENSE_SPDX(BSD-3-Clause LGPL-2.1+)

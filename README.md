Description
===========

a block to log to an hdf5 file

Requirements
============

[HDF5 for lua](http://colberg.org/lua-hdf5/)

Instructions
============

See the [wiki]

To do
=====

- port capable of sending hdf5 file to another block (hdf5\_sender)
	- use of struct with int leng and char[leng]?
	- use of type {class=...,name=hdf5_file}?
- port capable of receiving time information
- create numbered states if timestamp=0
- fix datatype problem with the trig\_rand integers
- config will have an array of data to be written from port/block combo (struct)
- data type is discovered? --> possible?

[wiki]: https://github.com/ejans/hdf5_logging/wiki


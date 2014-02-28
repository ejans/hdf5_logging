Description
===========

A block to log to an hdf5 file

Instructions
============

See the [wiki].

Overview
========

Requires [HDF5 for lua](http://colberg.org/lua-hdf5)

License
=======

This software is published under a dual-license: GNU Lesser General Public License LGPL 2.1 and BSD license. The dual-license implies that users of this code may choose which terms they prefer.

Acknowledgment
==============

The research leading to these results has received funding from the
European Community's Seventh Framework Programme under grant
agreement no. FP7-600958 (SHERPA: Smart collaboration between Humans and
ground-aErial Robots for imProving rescuing activities in Alpine
environments)

Task List
=========

- cleanup c errors by knowing what groups have already been created
- port capable of sending hdf5 file to another block (hdf5\_sender)
	- use of struct with int leng and char[leng]?
	- use of type {class=...,name=hdf5_file}?
- port capable of receiving time information
- create numbered states if timestamp=0
- fix datatype problem with the trig\_rand integers
- config will have an array of data to be written from port/block combo (struct)
- data type is discovered? --> possible?

[wiki]: https://github.com/ejans/hdf5_logging/wiki


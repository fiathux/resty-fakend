# About

项目整理中，暂时不要提交任何代码

This project need be re-origanized. do not commit any code until it ready.

Resty-fakend is a light weight development framework of Web backend, which based on Openresty.

The framework provide following features:

- Write your Web backend in Lua;
- Full life-circle control for Web API access;
- Cache and database support and MVC-like development mode;
- Full REST style support;
- Work and debug in docker;
- Auto dependence support and incremental update and deploy tool-chain (based on Makefile).

# Source Path

```
-+-- _scaner.py   : project scaner and updater
 +-- downpackages : external dependences (config and packages)
 +-- luaentry     : framework entry point
 +-+ lualib       : framework codes and core libs.
   |
   +-- framework/baas           : some APIs that to port Droi BaaS programs
   +-- framework/logger         : a log module that compatiable Droi BaaS APIs
   +-- framework/redisconn      : a connection that port Droi BaaS cache API to redis
   +-- framework/restyctr       : REST style controller
   +-- framework/spinlock       : a spinlock implementation
   +-- share/utils/random.lua   : a global random value and string generator
   +-- share/utils/uricodec.lua : an URI codec module
   +-- share/calendar.lua       : a calendar tool module, compatiable Julian in history calendar
   +-- share/functional.lua     : a functional programing support module
   +-- share/paramchk.lua       : a parameter auto check framework
 +-- misc         : assist components
 +-- package_template   : docker and deploment files
 +-- restyconf_template : nginx config template
 +-- sample_proj  : sample files
```

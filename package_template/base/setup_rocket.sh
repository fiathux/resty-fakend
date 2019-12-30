#!/bin/bash

# install luasocket
echo "============= Install Lua Package ============="
luarocks install luasocket
luarocks install lua-cjson
luarocks install luafilesystem
luarocks install luasec
luarocks install copas
#luarocks install lua-mongo
luarocks install lua-resty-rsa
echo ""
mv /home/setup_rocket.sh /home/backup
echo "Complete!"


#!/bin/bash

# Update package
mkdir /home/depsource
echo "Start install"
# install openresty
echo "============= Install OpenResty ============="
cd /home/depsource
curl -L http://gitlab.droi.cn/frame/public-images/raw/master/resty_youliao/openresty-1.15.8.2.tar.gz>openresty-1.15.8.2.tar.gz
curl -L http://gitlab.droi.cn/frame/public-images/raw/master/resty_youliao/zlib-1.2.11.tar.gz>zlib-1.2.11.tar.gz
tar xvzf zlib-1.2.11.tar.gz
tar xvzf openresty-1.15.8.2.tar.gz
cd openresty-1.15.8.2
./configure --with-pcre --with-zlib=../zlib-1.2.11
make install
echo "============= Install Lua ============="
cd /home/depsource
curl -L http://gitlab.droi.cn/frame/public-images/raw/master/resty_youliao/lua-5.1.5.tar.gz>lua-5.1.5.tar.gz
tar xvzf lua-5.1.5.tar.gz
cd lua-5.1.5
make linux
make install
echo "============= Install Luarocks ============="
cd /home/depsource
curl -L http://gitlab.droi.cn/frame/public-images/raw/master/resty_youliao/luarocks-3.0.3.tar.gz>luarocks-3.0.3.tar.gz
tar xvzf luarocks-3.0.3.tar.gz
cd luarocks-3.0.3
./configure --with-lua=/usr/local/
make install
luarocks install lua-resty-http
echo "============= Install Mongo-C-Driver ============="
cd /home/depsource
curl -L http://gitlab.droi.cn/frame/public-images/raw/master/resty_youliao/mongo-c-driver-1.13.0.tar.gz>mongo-c-driver-1.13.0.tar.gz
tar xvzf mongo-c-driver-1.13.0.tar.gz
cd mongo-c-driver-1.13.0
cmake -DENABLE_AUTOMATIC_INIT_AND_CLEANUP=OFF
make
make install
ln -s /usr/local/lib64/libbson-1.0.so.0 /lib64
ln -s /usr/local/lib64/libmongoc-1.0.so.0 /lib64/
echo "============= Clean ============="
echo "Please wait..."
cd /
rm -rf /var/cache/dnf/*
rm -rf /home/depsource/*
mkdir /home/backup
mv /home/install.sh /home/backup
echo "=========================================="
echo "Complete!"


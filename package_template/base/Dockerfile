FROM centos:centos8
ENV container docker
RUN dnf -y update
RUN dnf -y install perl make cmake3 gcc-c++ gcc readline-devel openssl-devel which unzip pcre-devel cmake git
ADD install.sh /home/install.sh
RUN sh /home/install.sh
ADD setup_rocket.sh /home/setup_rocket.sh
RUN sh /home/setup_rocket.sh
CMD /usr/local/openresty/bin/openresty -p /home/deploy -c /home/deploy/conf/bootresty.conf;

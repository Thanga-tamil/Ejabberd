FROM asia-south1-docker.pkg.dev/ting-messenger/tm-artifact-registry/erlang24:v5
### Expose the ejabberd ports ###
EXPOSE 5222
EXPOSE 5269
EXPOSE 5281
### Maintain same erlang cookie for ejabberd cluster ###
RUN useradd -m ejabberd
COPY .erlang.cookie /home/ejabberd/
COPY .erlang.cookie /root
RUN chmod -R 600 /home/ejabberd/.erlang.cookie /root/.erlang.cookie
RUN chown -R ejabberd:ejabberd /home/ejabberd/.erlang.cookie /root/.erlang.cookie
RUN mkdir /opt/ejabberd
RUN apt-get update && apt-get install -y dnsutils vim

COPY MirrorFly.py /opt/ejabberd/MirrorFly.py
RUN chmod +x /opt/ejabberd/MirrorFly.py
RUN mkdir -p /opt/ejabberd/certs
COPY limits.conf /etc/security/limits.conf
### for kafka ###
# RUN apt-get update && apt-get install -y libsasl2-dev liblz4-dev libzstd-dev libcurl4-openssl-dev
### Move Source code files  and Install ###
COPY . /tmp/ejabberd/
RUN chmod -R 755 /opt/
RUN cd /tmp/ejabberd; ./autogen.sh; ./configure --with-rebar=rebar --enable-user=ejabberd --enable-mysql --prefix=/opt/ejabberd
RUN cd /tmp/ejabberd; make; exit 0
RUN cd /tmp/ejabberd; cp xmpp_codec.spec deps/xmpp/specs/xmpp_codec.spec
RUN cd /tmp/ejabberd/deps/xmpp; make spec; make
RUN cd /tmp/ejabberd; make
COPY rabbit_common.app  /tmp/ejabberd/deps/rabbit_common/ebin/rabbit_common.app
RUN cd /tmp/ejabberd; make install

RUN chown -R ejabberd:ejabberd /opt/ejabberd
RUN chmod -R 755 /opt/ejabberd
### remove source code from the container
RUN rm -rf /tmp/es.rpm

# Copy the startup script into the container
COPY cluster-join-leave.sh /usr/local/bin/cluster-join-leave.sh
# Ensure the script is executable
RUN chmod +x /usr/local/bin/cluster-join-leave.sh
# Set the script as the entrypoint or part of the command
CMD ["/usr/local/bin/cluster-join-leave.sh"]

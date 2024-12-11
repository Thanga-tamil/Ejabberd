FROM nexus-demo.contus.us:8446/mirrorfly-uikit/prod/erlang24:v1

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

#COPY MirrorFly.py /opt/ejabberd/
COPY MirrorFly.py /opt/ejabberd/MirrorFly.py

RUN chmod +x /opt/ejabberd/MirrorFly.py

RUN mkdir -p /opt/ejabberd/certs
COPY limits.conf /etc/security/limits.conf
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

### install tini

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

### Move configs to etc ###

#COPY etc /opt/ejabberd/etc
RUN chown -R ejabberd:ejabberd /opt/ejabberd
RUN chmod -R 755 /opt/ejabberd

### remove source code from the container

RUN rm -rf /tmp/es.rpm
#RUN rm -rf /opt/ejabberd/source

### The application's jar file ###

# ARG JAR_FILE=ejabberdadmin.jar

# ###  Add the application's jar to the container ###

# ADD ${JAR_FILE} ejabberdadmin.jar

###  Run the jar file ###

# Copy the startup script into the container
COPY cluster-join-leave.sh /usr/local/bin/cluster-join-leave.sh

# Ensure the script is executable
RUN chmod +x /usr/local/bin/cluster-join-leave.sh

# Set the script as the entrypoint or part of the command
ENTRYPOINT ["/usr/local/bin/cluster-join-leave.sh"]

# ENTRYPOINT ["/tini", "--", "/entrypoint.sh"]
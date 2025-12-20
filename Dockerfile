# Use the official Erlang image as the base
FROM erlang24

# Create ejabberd user and home directory
RUN useradd -m ejabberd

# Copy the Erlang cookie and set the appropriate permissions
COPY .erlang.cookie /home/ejabberd/
COPY .erlang.cookie /root
RUN chmod -R 600 /home/ejabberd/.erlang.cookie /root/.erlang.cookie
RUN chown -R ejabberd:ejabberd /home/ejabberd/.erlang.cookie /root/.erlang.cookie

# Create necessary directories
RUN mkdir /opt/ejabberd
RUN mkdir -p /opt/ejabberd/certs

# Copy and set permissions for additional files
COPY MirrorFly.py /opt/ejabberd/MirrorFly.py
RUN chmod +x /opt/ejabberd/MirrorFly.py
COPY limits.conf /etc/security/limits.conf

# Copy source code and set permissions
COPY . /tmp/ejabberd/
RUN chmod -R 755 /opt/

# Build and install ejabberd
RUN cd /tmp/ejabberd; ./autogen.sh; ./configure --with-rebar=rebar --enable-user=ejabberd --enable-mysql --prefix=/opt/ejabberd
RUN cd /tmp/ejabberd; make; exit 0
RUN cd /tmp/ejabberd; cp xmpp_codec.spec deps/xmpp/specs/xmpp_codec.spec
RUN cd /tmp/ejabberd/deps/xmpp; make spec; make
RUN cd /tmp/ejabberd; make
COPY rabbit_common.app  /tmp/ejabberd/deps/rabbit_common/ebin/rabbit_common.app
RUN cd /tmp/ejabberd; make install

# Set ownership and permissions for ejabberd directory
RUN chown -R ejabberd:ejabberd /opt/ejabberd
RUN chmod -R 755 /opt/ejabberd

# Switch to ejabberd user
USER ejabberd

# Expose necessary ports
EXPOSE 5222 5269 5281

# Set entrypoint and default command
ENTRYPOINT ["/opt/ejabberd/sbin/ejabberdctl"]
CMD ["foreground"]


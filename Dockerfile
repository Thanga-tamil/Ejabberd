FROM erlang24:latest

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

RUN touch /opt/ejabberd/sso-auth.log

COPY limits.conf /etc/security/limits.conf
### Move Source code files  and Install ###

COPY . /tmp/ejabberd/
RUN chmod -R 755 /opt/
RUN chmod 666 /opt/ejabberd/sso-auth.log
RUN cd /tmp/ejabberd; ./autogen.sh; ./configure --with-rebar=rebar --enable-user=ejabberd --enable-mysql --prefix=/opt/ejabberd
RUN cd /tmp/ejabberd; make; exit 0
RUN cd /tmp/ejabberd; cp xmpp_codec.spec deps/xmpp/specs/xmpp_codec.spec
RUN cd /tmp/ejabberd/deps/xmpp; make spec; make
RUN cd /tmp/ejabberd; make
COPY rabbit_common.app  /tmp/ejabberd/deps/rabbit_common/ebin/rabbit_common.app
RUN cd /tmp/ejabberd; make install
### Startin the ejabberd server ###

CMD ["/opt/ejabberd/sbin/ejabberdctl", "foreground"]

# Set entrypoint and default command
ENTRYPOINT ["/opt/ejabberd/sbin/ejabberdctl"]
CMD ["foreground"]


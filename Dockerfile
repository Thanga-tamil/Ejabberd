### Erlang Base Image  ###

#FROM fly-nexus.contus.us:8445/erlang21:v1
#FROM hyd.ocir.io/axvlhlx5qpcs/mirrorfly-preprod/erlang23:sandbox-v1
FROM nexus-demo.contus.us:8446/mirrorfly-uikit/prod/erlang23:v1
### Expose the ejabberd ports ###

EXPOSE 5222
EXPOSE 5269
EXPOSE 5443
EXPOSE 5280
EXPOSE 5281

### Working directory ###

RUN mkdir /opt/ejabberd
RUN chmod -R 755 /opt/
WORKDIR /opt/ejabberd

ARG ENVIRONMENT='Dev'

#COPY MirrorFly.py /opt/ejabberd/
COPY MirrorFly.py /opt/ejabberd/MirrorFly.py



RUN yum install python-requests -y

### Move Source code files  and Install ###

COPY . ./
RUN ./autogen.sh
RUN ./configure --prefix=/opt/ejabberd -enable-mysql
RUN make; exit 0
RUN cp xmpp_codec.spec deps/xmpp/specs/xmpp_codec.spec
#RUN cp rabbit_common.app  deps/rabbit_common/ebin/rabbit_common.app
RUN cd deps/xmpp/; make spec; make
RUN make
RUN cp rabbit_common.app  deps/rabbit_common/ebin/rabbit_common.app
RUN make install

RUN yum install -y python-pip python3
RUN pip3 install requests && pip3 install PyJWT
RUN yum update -y
RUN chmod +x /opt/ejabberd/MirrorFly.py
### Startin the ejabberd server ###

CMD sbin/ejabberdctl foreground

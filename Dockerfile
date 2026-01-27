# ---------- STAGE 1: build sso-auth ----------
FROM golang:1.25.5 AS sso-builder

WORKDIR /build

# Copy only Go source (adjust path if needed)
COPY ssoauth.go .

# Build static binary to avoid glibc issues entirely
ENV CGO_ENABLED=0
RUN go build -o sso-auth ssoauth.go


# ---------- STAGE 2: ejabberd runtime ----------
#FROM nexus-demo.contus.us:8446/mirrorfly-uikit/prod/erlang25:v1
FROM asia-south1-docker.pkg.dev/ting-messenger/tm-artifact-registry/erlang24:v5
EXPOSE 5222 5269 5281

RUN useradd -m ejabberd
RUN mkdir -p /opt/ejabberd

# Erlang cookie
COPY .erlang.cookie /home/ejabberd/
COPY .erlang.cookie /root
RUN chmod 600 /home/ejabberd/.erlang.cookie /root/.erlang.cookie && \
        chown ejabberd:ejabberd /home/ejabberd/.erlang.cookie

# Base packages
RUN apt-get update && apt-get install -y \
        dnsutils \
        libyaml-0-2 \
        && ldconfig

# Copy Go binary built inside Docker
COPY --from=sso-builder /build/sso-auth /opt/ejabberd/sso-auth
RUN touch /opt/ejabberd/sso-auth.log
RUN chmod +x /opt/ejabberd/sso-auth

RUN mkdir -p /opt/ejabberd/certs
COPY limits.conf /etc/security/limits.conf

# ejabberd build (unchanged)
COPY . /tmp/ejabberd/
RUN chmod -R 755 /opt/
RUN cd /tmp/ejabberd; ./autogen.sh; ./configure --with-rebar=rebar --enable-user=ejabberd --enable-mysql --prefix=/opt/ejabberd
RUN cd /tmp/ejabberd; make; exit 0
RUN cd /tmp/ejabberd; cp xmpp_codec.spec deps/xmpp/specs/xmpp_codec.spec
RUN cd /tmp/ejabberd/deps/xmpp; make spec; make
RUN cd /tmp/ejabberd; make
COPY rabbit_common.app  /tmp/ejabberd/deps/rabbit_common/ebin/rabbit_common.app
RUN cd /tmp/ejabberd; make install

# Permissions
RUN chown -R ejabberd:ejabberd /opt/ejabberd && \
        chmod -R 755 /opt/ejabberd

RUN rm -rf /tmp/es.rpm

# Copy the startup script into the container
COPY cluster-join-leave.sh /usr/local/bin/cluster-join-leave.sh
# Ensure the script is executable
RUN chmod +x /usr/local/bin/cluster-join-leave.sh
# Set the script as the entrypoint or part of the command
# CMD ["/usr/local/bin/cluster-join-leave.sh"]

# Add wrapper entrypoint
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]
CMD []

# A throwaway sshd for RayonSSH's live tests (run-live-tests.sh builds it).
FROM alpine:3.20
RUN apk add --no-cache openssh openssh-sftp-server socat \
 && ssh-keygen -A \
 && adduser -D -s /bin/sh rayon \
 && echo 'rayon:rayon-password' | chpasswd \
 && mkdir -p /home/rayon/.ssh && chmod 700 /home/rayon/.ssh \
 && sed -i -E '/^#?(AllowTcpForwarding|PasswordAuthentication|Subsystem)/d' /etc/ssh/sshd_config \
 && printf '%s\n' \
    'PasswordAuthentication yes' \
    'AllowTcpForwarding yes' \
    'Subsystem sftp internal-sftp' \
    >> /etc/ssh/sshd_config
# On the container's loopback, for the forwarding tests: an echo service,
# and one that greets and hangs up before the client is done.
CMD ["/bin/sh", "-c", "socat TCP-LISTEN:9000,bind=127.0.0.1,fork,reuseaddr EXEC:cat & socat TCP-LISTEN:9001,bind=127.0.0.1,fork,reuseaddr SYSTEM:'echo hello' & exec /usr/sbin/sshd -D -e"]

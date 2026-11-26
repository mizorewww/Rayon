# A throwaway VNC server behind sshd for VNCLiveTests (run-vnc-live-tests.sh
# builds it). The desktop is random noise, so every full frame is several MB
# whatever the encoding.
FROM alpine:3.20
RUN apk add --no-cache xvfb x11vnc openssh imagemagick \
 && ssh-keygen -A \
 && adduser -D -s /bin/sh rayon \
 && echo 'rayon:rayon-password' | chpasswd \
 && sed -i -E '/^#?(AllowTcpForwarding|PasswordAuthentication)/d' /etc/ssh/sshd_config \
 && printf '%s\n' 'PasswordAuthentication yes' 'AllowTcpForwarding yes' >> /etc/ssh/sshd_config \
 && magick -size 1280x800 xc: +noise Random /noise.png \
 && x11vnc -storepasswd vnc-password /vncpass
CMD ["/bin/sh", "-c", "Xvfb :0 -screen 0 1280x800x24 & sleep 1; DISPLAY=:0 display -window root /noise.png; x11vnc -display :0 -rfbauth /vncpass -forever -shared -localhost -rfbport 5900 -quiet & exec /usr/sbin/sshd -D -e"]
